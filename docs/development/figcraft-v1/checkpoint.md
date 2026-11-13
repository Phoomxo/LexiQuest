# Continuous execution checkpoint

Updated 2026-11-14, approximately 06:01 Bangkok. Running work, not a pause or completion.

## Authority and source

- Worktree: C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest
- Branch: codex/figcraft-flutter-prototype
- Verified and pushed UI integration: 196d4e22b3e4365fba22d36198cb07762d95b981. A Linux-golden-only correction is being committed; Android production sources remain identical. Inspect actual Git HEAD before any build.
- Draft PR: https://github.com/Phoomxo/LexiQuest/pull/16, base codex/current-code-20261113.
- The active continuous Goal includes the Android camera/set-A milestone and all approved S1–S7 work. Keep the denominators 48 screens / 44 features / 64 packages. Do not close the Goal after one card.
- No merge, deployment, publication, real enrollment/upload, app data clearing, destructive cleanup or Codex Security workflows. Preserve generated plugin line-ending churn and ignored signing configuration. Use only the task worktree for edits.

## Current source and verification

- Root completed final full verification session 83069: clean analysis (19.2s), 26 changed/new Dart files formatted with zero changes, and all 1,903 Flutter tests passed in build/p2-s3-full-test-final.txt.
- All 517 input files stayed identical. Final before/after manifests have SHA-256 0c69d935b9d228248e06279b6d82b276fe214737879a9ef4b9dfad0d4bfaf2ff. A fresh precommit comparison also found zero changes. See evidence/p2-s3-local.txt and p2-s3-inputs.tsv. Flutter3.44.7/Dart3.12.2 were read from the installed SDK.
- The earlier full run1902/one failure exposed Source Voice's wrong return label. The original assertion stayed. Quiz now carries explicit origin labels through fallback/Score/nested repair; Source returns to activities, history returns to its saved result, and direct category practice retains its set return. Targeted9 and finalfull1903 passed; final independent review accepted.
- The Flutter queue is currently clear. Root stores figcraft_flutter_session and checks it before every Flutter/Gradle operation. All future full checks must have frozen writers and before/after input manifests.

## Active writers and next executable steps

- All production/test writers are frozen. Root owns integration and native builds. S6 candidate-a (gpt-6-astra) and candidate-b (gpt-6.1-sol) may write only isolated build/architect-s6 text sketches; these are outside verified compile inputs. Do not start S6 implementation/migration before synthesis and the UI build snapshot are closed.
- Current source reviews are accepted. Linux-only expected-image correction bbb63b7c is pushed. Do not repeat full Windows tests for it. CI43520187537 passed1901 and failed only Home/Quiz Linux goldens; actual artifacts were opened by root and independent reviewer before copying. See evidence/p2-s3-linux.txt. Current-head run43522858276 has reached Flutter tests; final CI remains required.
- Commit/push only intended source/tests/goldens and evidence. Update this checkpoint, decisions, execution board and PR body around the verified result. Follow CI on that exact PR head; inspect actual Linux image artifacts before updating Linux goldens.
- Both v29 APK builds from196d4e22 completed and are archived under build/figcraft-196d4e22. See evidence/v29-builds.txt for hashes/flags. Vivo's actual installed APK hash matches the archive. A3/latest67 and B0 survived update and offline cold restart. Root and independent reviewer accepted the captured dark100/200% Home/Library/Score states, not TalkBack. evidence/vivo-196d4e22 has28 validated raw files,14 PNG/XML pairs, including the preupdate baseline. Four A hierarchies before/after/update/offline/restoration have identical hashes. Font/Wi-Fi/keyboard/accessibility settings are restored. No new answer/word/camera operation in this retest.
- Emulator install-r session1837, task-owned client PID26488, has no acknowledgement/log output. Last readonly get-state returns device; shell ps times out and host instance18 remains running. Do not duplicate install, kill a possible package transaction, reboot, clear or reseed to force progress. Stop affected writes and continue independent work; inspect/reconcile actual version/install state when responsive. New P2 comparison images remain pending on that path.
- Continue remaining S3/S5/S6/S7 work and reconcile every ledger row. Static ledgers are a cache at67a68518, not current acceptance evidence. No separate Pair Matching task is authorized.

## Accepted local cards in the dirty UI slice

- Theme/Home/Library: pinned FigCraft light palette and typography, 104/160dp root headers, growable controls and one lazy scrollable library body. Ocean/dark roles remain composed from their seed. The corrected Windows Home and Quiz feedback renders were opened before normal golden updates. A raw button TextStyle dropped the Thai font; it now inherits the Thai label style.
- Library scope/landscape/stale actions: 23 checks GREEN. Selected routes fail closed after scope replacement; root library follows current authority; stale add/delete/retry/search callbacks cannot restore A. The constant scroll-view key avoids re-listening to a single-subscription library stream when query text changes.
- Quiz: honest one-choice fallback, normal Add Word callback and original owner/category pin; no fake score/reward or B distractor. Formula, SRS and Shadowing domain behavior remain unchanged. Edit forms reject changed owner/scope before writes. Scope/generation guards and frozen repair fields prevent stale Score callbacks and disposed Quiz getter access.
- Shared Score: original dependency scope is pinned; a replacement/removal removes old artifacts and guards rendered repair/return actions by current scope and route. Direct nine-case RED plus standalone control preceded implementation. Same-provider owner changes without a scope event are not generally claimed covered.
- Weakness: seven new checks GREEN and independently accepted. Rebind current scoped sources, clear prior FutureBuilder data, reject old callbacks/late futures, preserve standalone injection.
- Profile freshness: real SRS practice → account tab → two saved metric updates; ordinary rebuilds do not duplicate reads. The focused account/profile/shell set passed 23. Refined feature-collapse behavior passed unchanged production; the proposed clamp bug was disproven, so no clamp fix was made.
- Actual logout navigation: clean RED exposed Back during pending signOut leaving A visible. An eight-line Settings fix uses existing busy state for PopScope/AppBar Back, keeping the route alive until success/reset or failure/rollback. Actual MyApp + real Drift tests preserve A and empty guest invariants. Final logout/Profile set: five GREEN, independently accepted.
- Recovery focus: seven GREEN in build/p2-s3-recovery-focused.txt, including saved Score scope changes, exact latest result, source nested/nested-burst and shell scroll. Earlier broad run 84815 was partial (232 passed, seven failed, two did not complete); its blocked synthetic Quiz process was identified and stopped. Logout fixture's first blocked process was likewise identified and stopped. Both fixture zone/cleanup issues were corrected; neither aborted run is product acceptance.
- S5 full-account export is already committed at 069ab015: 76 tests, final eight-test rerun, clean scoped analysis and independent approval. evidence/s5-full-export-local.txt records source hashes. It saves actual synthetic JSON bytes before issuing a receipt; ordinary export cannot claim full-account coverage. Live deletion UI/bootstrap/reauthentication remains disabled.
- Earlier S5 scope commit cd45d6a5 passed 377 focused checks and 47 final account checks. CI 43502724423 on 069ab015 failed the old Mastery owner-read-count fixture. Its behavior-based readiness correction is in the current dirty slice and passed all 26 Mastery tests. Do not represent old CI as current-head GREEN.

## Native evidence and device state

- Native milestone source 08ce39bcca697d903ec79ca15c52d9ac66b0d391: full local 1,821/1,821 and clean analysis; signed arm64 v28 APK SHA-256 34a614b7fc9bd49ac743a4cc551099c649aa23636791417c43240fb6cbe4546f, archived under build/figcraft-08ce39bc/. Debug x64 SHA-256 25b76cb6e177616c42c7855d103d612bdd009ad62bca7e69beef38a69c8c7528.
- Vivo actual capture returned no confident proposal. Manual synthetic mug/แก้ว/noun was explicitly saved into A, practiced with station/ticket, produced 67% (2/3), returned to A and reopened offline with the same words/result. B remained empty. No native session UUID or model-accuracy claim. The user cannot position a known object; do not ask again.
- Committed evidence/vivo-08ce39bc contains 64 raw files (62 acceptance, two excluded startup diagnostics). Four core images were shown in chat. Earlier 984e6164 JSON fallback is separate and must never be called camera-save success.
- Committed evidence/android-08ce39bc contains two actual FigCraft/Android comparisons, metadata/manifests and the independent 28/40 critique. Shown in chat. P2 native visual alignment, TalkBack, and unobserved empty/error/new-owner states remain pending.
- Vivo serial 9582188822004C6 is root-owned; last idle on A with three words/latest67. Last restored: font1.0, Wi-Fi1, mobile0, accessibility off, Gboard. Read current state before next device mutations and restore that state afterward.
- Emulator emulator-5590 is root-owned; last restored physical1280x720, density240, no overrides, font null, night no/accessibility off. Synthetic state: two sets, three words, platform due1, consent/session/attempt/outbox zero. Preserve it; no reseed/uninstall/clear. Two corrective reboots resolved its earlier system-server stall; no blind new reboot.
- tool/figcraft/capture_android.py validates fresh XML/PNG and refuses existing evidence prefixes. tool/figcraft/compare_android.py uses actual pixels. CUA has not been initialized.

## S6 grounded next card, not implementation

- Root read the actual ledger and schema: current v10, v11 unreserved. No schema reservation or S6 source edit has occurred.
- P4.4/f29/f30 map to the existing Mastery screen; do not add a 49th canonical screen.
- Before wiring: Quest recurrence is blocked by UNIQUE(owner_id, quest_id); replay evidence and atomic progress need stable immutable attempt IDs. Streak hooks must carry the committed owner/time; current progress uses UTC-day streaks and no learner IANA authority exists. Do not infer IANA from timeZoneName.
- A complete card needs recurrence/history migration safety, atomic replay, owner/time/zone boundaries and real UI/reopen behavior. Quest XP must use the existing reward authority and must not become accidental coins through legacy positive-XP carry. Keep Pair Matching untouched.
- Grounding references: evidence/s5-impact.md and s6-impact.md. Synthetic/emulator implementation may continue despite missing external research authority; real enrollment/upload stays default-off.
