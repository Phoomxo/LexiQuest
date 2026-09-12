# Stabilization 1–6 — current evidence

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`. User authorized priorities 1–6. Inherited changes preserved; no commit, deployment, data clear or uninstall.

Evidence prefixes below: **S** = `build/verification/stabilization-1-6-20260910`; **A** = `build/verification/motivation-ui-20260908`. Earlier chronological ledger is archived in S/results-before-consolidation.md; its running-status statements are historical.

## Current checkpoint

- User decision on 2026-09-10: accept **2h48m28s** for this iteration ("เอา 2 ชั่วโมง 48 นาที 28 วินาที ไปก่อน"). No fresh three-hour run is required now. This changes the iteration's acceptance scope; it does not change the failed runner journal or establish final phase/cleanup success. Only documentation changed after the verified source/build; the plan edit changes the whole-source fingerprint, not the delivered APK code.
- 2026-09-11 closure: vivo reconnected as ADB serial `9582188822004C6`, charging at 100%. Exact reconciliation required fixture SHA `23bd23452b5f541df4d63d0421872ea58851f82b17d1952ffad4ee9a66914dc9`, run UUID `e4925ef5-cdfd-4060-8088-c70da13c7ddc`, and both fixture owner markers before action. The 287-file exclusively owned synthetic root was archived under S/endurance-disconnect-recovery, then removed. Compatible manual APK SHA `d376304c38809931c2aa7c9cb771690e11e660a8285f3ae9f8f3043defe5ba2e` was installed and verified twice; no pending reconciliation remains.
- Temporary vivo logging is now off: `persist.sys.log.ctrl=no`, `persist.sys.vivolog.state=off`. The Feedback draft was blank and its Submit control disabled; no upload was made. “Stop and exit” was not confirmed because it would clear global logs. Temporary XML inspection files were removed. Accessibility remains restored (`enabled_accessibility_services=null`, `accessibility_enabled=0`).
- Completed: application/controller recovery, Thai UI labels, native export roundtrips, integration checks and ordinary test APK, bounded actual TalkBack navigation.
- Fresh smoke A/r14-smoke-route-ready-v2 PASS: 371,069 ms (6m11s), 59 completed sessions; every phase oracle passed, source stable, exact owned cleanup and compatible restore verified, no errors/pending reconciliation.
- Fresh three-hour run **A/r14-endurance-full-route-ready FAILED after battery exhaustion/disconnection**. Session 1988 has exited and is no longer available. Last durable checkpoint: 10,108,141 ms (2h48m28s), 1,148 sessions at 2026-09-10T10:49:18.310185Z. Last battery sample at 10:49:44Z was 0%, 36.3 C. ADB subsequently lists no devices. No 180-minute acceptance is claimed; elapsed time from failed runs is not added.
- Phases 0 and 1 passed; phase 2 did not finish. Last checkpoint has zero active sessions, foreign-owner rows, duplicate answer/reward IDs and research rows. Source/input pins remained stable. This is checkpoint evidence, not final endurance acceptance.
- Run UUID `e4925ef5-cdfd-4060-8088-c70da13c7ddc`; last device PID 5878 is historical and must be revalidated after reconnect. Restore and owned cleanup are unverified/false. Pending: cancel-transport-or-authority-unsettled, owned-forward, cleanup-or-restore, flutter-log-policy. The runner attempted cancellation after transport loss; its result is uncertain. No manual cancellation was issued before the disconnect. Preserve the failed journal and reconcile actual device state before any write or install.
- Temporary OEM logging was last observed active under explicit authorization; current state is unknown while disconnected. No upload was requested. TalkBack and temporary synthetic keyboard were restored/removed before this run.
- Source fingerprint at verified gates/build: `b1098e918fec764ab130a589c0e4e133eea71f739a39a15ef81d338ccc543247`. Do not alter pinned source or device UI during endurance.

## 1. Recovery and test controller

Original failed run recovered with exact UUID/PID/APK ownership and nine archived files; compatible APK restored. S/recovery-result.json and fresh-recovery-audit contain evidence. No learner database clear/uninstall.

Controller now distinguishes authenticated terminal SDK failure/success from an active workload, without weakening failure/native-log oracles. It preserves PID/epoch-filtered log evidence across ring rollover and handles Windows atomic-journal rename locks with two bounded same-payload recovery attempts. Forty-one host tests pass (S/controller-route-final.log).

Native test readiness now waits for mounted incoming/outgoing route animations and actual hit testing before scrolling/tapping. Two host navigation regressions pass (S/route-wait-final.log). Target pin `62a6278998f914e89c7273093fca952e2543e2dae2b3c1910cbfe6118bce4c66`.

## 2. Thai labels and reading defect

Learning preference goals/activities, form states and catalog empty/unavailable copy now use Thai presentation labels; serialized enum values are unchanged. Four screen tests include 200% text and absence of raw enum names.

A real vivo reading-completion defect was reproduced on the host: microsecond terminal identity disagreed with millisecond session storage. Auto-generated checkpoints now use the durable session timestamp. Tests verify completion, reopening, idempotent replay and rejection of a genuinely different millisecond. Shared authorization contracts are unchanged. Combined reading/controller/accessibility tests: 241 pass (S/reading-accessibility-subsystems.log).

## 3. PDF / Anki / JSON

All five export formats generated through real ExportUseCases from synthetic data and saved/read byte-for-byte. PDF rendered and visually checked: one page, legible Thai, no clipping (S/pdf-preview.png).

Actual Android Save/readback/provider-delete/grant-revoke flows PASS with restore and no pending state:
- A/r14-native-pdf
- A/r14-native-anki-v2
- A/r14-native-researchJson-v2
- A/r14-native-ownerArchiveJson-v3

Anki suggested extension fixed from .txt to .tsv to match its MIME type; Android previously produced .txt.tsv. Full export subsystem/screens: 64 pass; host export runner: 33 pass. Exact failed Anki receipt recovery is recorded in S/anki-recovery-v4/result.json. No real research export was used.

## 4. Real-clock endurance

Current candidate: A/device/r14-endurance-route-ready.apk, SHA256 `23bd23452b5f541df4d63d0421872ea58851f82b17d1952ffad4ee9a66914dc9`; pinned build record alongside it. Restore artifact is current-source isolated manual APK SHA256 `d376304c38809931c2aa7c9cb771690e11e660a8285f3ae9f8f3043defe5ba2e`, compatible versionCode 14.

Failed runs remain failed:
- A/r14-endurance-full: last valid checkpoint 5,192,340 ms (86m32s), 722 sessions. First hour passed; second phase failed because fresh-round target was not hit-testable during a transition. Cleanup/restore passed, pending empty. This prompted the route-readiness repair.
- A/r14-smoke-route-ready: workload never started; Android post-install initialization created a process before the exclusive-start check. Exact installed APK/PID/start ticks and sole owned marker were reconciled, then stopped and restored. S/prelaunch-smoke-recovery/result.json confirms no pending state. Fresh v2 smoke subsequently passed.
- Earlier native-log, journal-lock, IME and reading failures/recoveries remain in their original evidence directories and archived chronological ledger.

Monitor current run with `python -X utf8 S/endurance-progress.py r14-endurance-full-route-ready` (expand S). It uses Windows delete-sharing so reading the live journal cannot block atomic replacement.

## 5. Integration and APK

- Selected Flutter regression: **5,587 pass, 0 fail/skip**, no reporter parsing errors (S/full-regression-final.summary.json). Normal generator refreshed stale final-plan artifacts; earlier failing run retained.
- Three separately executed actual CPU/XNNPACK model cases pass (S/litert-final.log). The inherited iOS Podfile contract remains outside Android evidence.
- All three host integration suites pass: core journey, controls, media (A/logs/integrations-20260910T054445146108Z). Core test now follows the actual randomly selected reading word and verifies its active-owner SRS row after reconciliation, preserving original vocabulary assertions.
- Analyzer: **0 errors, 0 warnings, 91 existing style infos, exit 1** (A/logs/analysis-20260910T055114988151Z); not represented as a green gate.
- Generated feature/final-plan contracts pass. Backend Voice 74, AI 106, LM 94 pass; external Voice integration excluded. Firestore emulator 175 pass; Auth emulator 3 pass; PowerShell CLI 25/25 pass. Exact paths remain in archived ledger.
- Ordinary debug APK: **A/device/lexiquest-stabilization-v15-debug.apk**, version **1.0.0+15**, 224,393,288 bytes, SHA256 `1bf5d43619c73b82f2bd5b02338f5fc873152c1d78b83598b368b75e7091b833`. Debug signer/package/version verified. S/ordinary-apk-v15/summary.json records stable-source build evidence. Archived only, not installed or published.

## 6. Actual TalkBack and cleanup

Actual vivo V2041/API 33 TalkBack 17.0.1.926549743 bound service and touch exploration were verified. The enhanced keyboard mapping was exercised through a temporary Android UHID keyboard; direct ADB key injection was diagnostic only. Actual accessibility focus and activation covered home → lesson configuration → question/answer → correct feedback → next question. Evidence: S/talkback-device/result.md and screenshots 13–42. No additional production defect was found in that bounded path.

Thai lesson lifecycle semantics now expose readable state and percentage instead of raw English enums; host tests cover every lifecycle. This does not certify every screen, physical gesture behavior, or human listening/pronunciation quality.

HID session exited 0; device absent from dumpsys input. Restored enabled_accessibility_services=null/absent and accessibility_enabled=0; font_scale remained 1.0. First-use TalkBack tutorial completed; optional notification permission denied. Synthetic manual fixture data remains isolated and must not be confused with learner data.

OEM logging was initially disabled. User explicitly authorized temporarily enabling it, without upload; privacy dialog was already absent on refresh. Visible Full Dump, Circulate Modem and Bluetooth options were deselected; System logs was selected and screen recording off. Lower offscreen options were not independently audited. Recording was last observed active. “Stop and exit” asks “Stop recording and clear logs?”; previous attempt was cancelled. Installed APK review proves this clears global log roots, so do not confirm it. S/vivo-log-code/cleanup-review.md documents the alternative: opening the Feedback draft stops recording for normal users without submitting; actual upload requires a separate action. This supersedes the earlier precaution against opening the draft. This cleanup has NOT yet been executed. Verify properties off, leave via Home, never submit or approve discard/clear, and restore only known changed selections.

## Remaining work

The user has accepted the existing duration; do not restart endurance. Recovery and temporary logging cleanup are complete. Preserve physical listening UAT and release-only limitations. No production/research readiness claim.
