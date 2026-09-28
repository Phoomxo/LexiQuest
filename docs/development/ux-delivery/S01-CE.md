# S01-CE — isolated native draft exact recovery

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`, branch `codex/ux-current-after-s01-bc`, HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`.

## Result

**PASS_NATIVE_SYNTHETIC_DRAFT_EXACT_BOOTSTRAP_TODAY_OS_RESTART.** Created fresh debug-only `com.lexiquest.app.nativeDraftCe` with separate Gradle output. CE sandbox path regression failed before the fixture change and passed after it. The build-time 840-file source closure stayed identical after the APK build and native run. APK SHA256: `19f9fe039948c74210a212b6717d72d7c59a221c2f5293d3cde7774e8a683b98`; manifest SHA256: `7a5f7568f101d78711bb1e14e5e6e0573634e072c8af8dc6fb1f1037ce8339a6`. APK ID matched, debug flag present, exactly one harness activity, and no forbidden permission, provider, receiver, service, VIEW or BROWSABLE component. Read-only V2041/API33 preflight found CE absent and eight protected package metadata records stable; install count was zero.

One CE native attempt installed CE once (`Success`) and ran D01–D05 with test-only synthetic data. Seed PID `4267`, verified absent after force-stop, resume PID `4627`. Actual AppBootstrap/Today restored the selected ordinary meaning draft. Seed/resume receipts matched the exact owner, session, frozen plan, selection `แมว`, index 0 and `awaitingAnswer` progress. All 58 table digests, fixture/progress/non-checkpoint event digests stayed equal; two checkpoint rows and zero answer rows. Wrong owner/session rejected. No duplicate scoring, SRS, reward, achievement, research/outbox or external operations. Protected metadata for eight packages and hashes of twelve prior APK files remained unchanged. Runner journal shows one install and one CE force-stop; no forbidden device command. Receipts and hashes are pinned in `evidence/S01-CE-checkpoint.json`.

Focused verification: 4 HOST fixture tests PASS; targeted CLI source/isolation/CD+CE contract and CB/CD/CE runner tests PASS (14 stub cases); three-file Dart analyzer clean; Gradle CE debug APK build PASS. Initial build command argument parsing and missing CE Google Services debug guard were diagnosed and corrected before the successful build. Neither failed build invoked an install. No production `lib`, schema, scoring, SRS, reward, route, gate or research source changed in this package.

## Remaining scope

Native stale-route/content revision and N05 visual/IME/TalkBack remain OPEN. Actual-user participation/trials remain deferred; frozen-source release is not accepted. CB's two historical install command counts remain `UNVERIFIED_UP_TO_TWO_ATTEMPTS`. Preserve CE/CD/CB and every earlier installed package and APK; do not reinstall/reseed or clean them. No successor dispatched.
