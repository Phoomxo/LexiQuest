# R15.9 AI Tutor verification — local accepted

Source: a85540c8792f23c3d994ac94db2fc0a6b90972d8, task worktree
C:/Users/Phet/.codex/worktrees/1093/LexiQuest,
feature/r15-ai-tutor-continuation. Solo local implementation, no live calls.

## Dependency scope decisions
- Gateway factory forwards the optional request context through circuit breaking;
  all affected controller/gateway test doubles need the optional signature.
- Gemini is an existing production default behind this same factory. Its native
  gateway and retry boundary must also carry the context; otherwise the new
  level/intent/history UI would silently lie for this provider. Extend only this
  optional transport contract and its tests, preserving retry/cancellation.
  No new endpoint, provider service, storage, or credential resolution.
- Settings expose an opaque local owner/credential scope, checked again under
  the existing owner gate before any accounted provider call. Scope/session IDs
  are never sent in provider bodies. New chat/scenario resets stay session-only.
- Composer and completed pairs are discarded when the local scope changes;
  preflight does not send a draft captured under an old owner. The UI checks the
  scope on local status refresh, route resume, before sending and after a reply.
  Existing owner-operation fencing protects the asynchronous provider call.

## Regression evidence
Logs under build/verification/a85540c8792f23c3d994ac94db2fc0a6b90972d8/:
- 70c79b9ceb09-41e53aa9bd06: null context expected160, actual120 (RED).
- 495900edca7c-e955b9d76434: context payload expected160, actual120 (RED).
- 54e07b220cd6-ca7beba546ab: owner scope expected nonnull, actual null (RED).
- 909382bb7147-5d279bd8288f: selectable reply/history missing (RED).
- 274fa91eb31e-304abd3cb5a9: 5 passed,1 failed. Multi-call owner fixture reused
  one usage event ID; durable accounting correctly rejected duplicate. Corrected
  fixture to unique IDs; no production accounting change.
- 1e5ed966cde8-f3c64bfabb43: Gemini practice expected480, actual120 (RED).
- 663ed1d3e882-0e2d1eeba140: stale-scope draft was sent (RED); preflight now
  resets and returns without an HTTP/accounting operation for that draft.
- 01bb7c1ed4fa-8f2f4020aabb: large-text offline reading viewport only66px,
  expected>300 (RED). Header/error now scroll with conversation, composer stays.
- 93a3e7660b6e-f16da1bd6c51: light visual passed; dark error was offscreen in
  the new scroll layout. Fixture now scrolls to the error before inspecting it.
  dce1b2c5f696dec735e497891d96449a7bb84987a8d72658af6c4fc4996a91a5
  targeted result confirms the dark recovery passed.
- Initial baseline target under build/ was rejected by verify-scope's test/
  allowlist before Flutter ran. Generated a task-owned test/screens fixture;
  baseline2tests passed, then removed only that temporary test. Baseline source
  is the exact accepted parent screen with imports adjusted for fixture location.
- Analyzer first found6 brace-style lints. Added braces around unchanged
  statements, formatted2files and reordered one import; final analyzer is clean.
- Plain diff-check treats historical CRLF as trailing whitespace in some tracked
  files. CRLF-aware `git -c core.safecrlf=false -c core.whitespace=cr-at-eol
  diff --check` passes. No whitespace rule or repository config was changed.

## Acceptance coverage
| IDs | Evidence and outcome |
| --- | --- |
| A-AI-01/02 | Immutable copied pairs; latest3pairs/3000codepoints; oversized pair omitted whole; Thai/emoji500/80/600 bounds; roles allow learner/tutor only. Adapter payload has prior roles then one latest learner message. |
| A-AI-03 | New chat/scenario/level/intent reset; owner/model/provider credential fence; unbound caller has no prior turns; cancelled/late replies excluded; owner-switch draft not sent. |
| A-AI-04/05 | Null=A1/conversation/nohistory; caps160/320/480 and configured90 test in all3adapters; unknown usage/cost stays unknown. Gemini factory/native retry path also gets context, A1 and intent caps. |
| A-AI-06 | Selectable plain text preserves Thai/Markdown-like text; pending question remains; failed/cancelled turn never forms a completed pair; new-chat stale result suppressed. |
| A-AI-07 | Real local sockets in3adapters: reply,401,402,429,malformed,timeout,cancel; exactly1request, role payload and no body credentials/sessionID. Client/server close in teardown. Separate use-case tests verify1accounted failure per category/owner, no guessed cost; existing owner gate tests retained. |
| A-AI-08 | Existing missing-key/settings/back and offline ordinary-learning paths pass; no auto purchase/subscription or live request added. |

## Final gates and source accounting
Commands ran serially through `tool/cli/verify-scope.ps1 -Level Targeted -Area AI
-TestTargets <paths>`, without TestName for these complete file suites:

1. `test/features/ai_tutor/{ai_gateway_adapters_test,ai_gateway_loopback_test,
   ai_tutor_use_cases_test}.dart` and `test/screens/ai_tutor_screen_test.dart`:
   **87passed, exit0**, gate17.00s (Flutter reports11s).
   Result:targeted-ai-d0d61df08d7ffc64b5d43475ab8014196cad177755ffdd1659f3e7a2ea2b895e.json.
   Log:9d09afe50255-80c0337cc4cd/Explicit-Flutter-tests.stdout.log.
   Fingerprint:80c0337cc4cde16a65865c0f091698fc8a787e8a98daa00d61c168a70beebc7b.
2. `test/features/gemini/{gemini_rest_gateway_test,retry_gemini_gateway_test,
   gemini_tutor_use_cases_test,ai_tutor_gateway_factory_test}.dart`,
   `test/screens/ai_tutor_settings_screen_test.dart`,
   `test/scenarios/{ai_voice_fallback_journey_test,runtime_kill_switch_journey_test}.dart`,
   `test/features/ai_tutor/owner_operation_coordinator_test.dart`:
   **50passed, exit0**, gate16.27s (Flutter reports11s).
   Result:targeted-ai-30a41bb1861d7c5c3c58936041e04ba195b5187fdf90e8386fcee8154ed35abc.json.
   Log:0887d0790315-b96fe3058e39/Explicit-Flutter-tests.stdout.log.
   Final fingerprint:b96fe3058e392469adfd467b6af3ad9217f6b8fedc9776763b4c068ae22cae8f.
3. `flutter analyze --no-pub <21 changed Dart paths>`:exit0,no issues,5.7s.
   Log:build/verification/r15-ai-analyze-final.log. Initial six lints remain in
   r15-ai-analyze.log; final formatter log:r15-ai-format-final.log.

**137 distinct tests in12targets**, with first suite retained across the six
lint-only brace insertions/formatting and one import reorder. Manual diff review
confirmed no execution change after those87passed. This is affected-scope
verification, not a full Flutter/backend/Android integration or release run.
No production source edits after the final gate. Source SHA256 manifest:
build/verification/r15-ai-final-source-manifest.json. Full gate records:
build/verification/r15-ai-execution-record.json. Logs are local and untracked.
Generated registrants have no content diff and are excluded from the commit.

## Visual QA and limits
Same synthetic fixtures captured accepted-parent before and revised after in
build/verification/r15-ai-visual/{before,after}-{false,true}-{empty,reply,reply-end,offline}.png.
NotoSansThai and MaterialIcons loaded;390px/light/100%,320px/dark/200%,844px high,
reduced motion. Opened before/after full screenshots; Thai and Markdown-like
words remain selectable/readable, scrolling exposes complete reply and error,
and the fixed composer remains reachable. Host fixture lacks an emoji glyph
(box in both baseline and after); rune/payload/text assertions preserve emoji.
This is not physical-device font verification. No SSE/streaming endpoint added.

Live teaching quality remains **live-not-run** (C-AI-Q external acceptance);
no provider/model/budget authorized for live calls. No real enrollment/upload,
research records, reward/learning writes or persistent chat history were added.
Physical/build integration belongs at combined UI freeze in R15.10.
No task-owned test/build/analyzer remains running. Token/credit usage unavailable.
Next:commit acceptedR15.9 and immediately dispatchR15.10 from exact acceptedSHA.
