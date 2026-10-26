# ADLC cycle 12 — external gates and Figma Login v15

Date: 2026-10-26 (Asia/Bangkok)

Branch: `codex/cycle12-release`

Source HEAD reviewed: `746ff702d9b13216eea164ddbed758942daf605d`

Disposition: scoped Login design and connected-Vivo evidence accepted; public
release remains gated by hardware, Play, production-control, and human-UAT
evidence.

## Intent and authority boundary

This continuation addressed the remaining evidence requested for physical
low/high/Fold/tablet devices, Play Console, production cloud, manual
TalkBack/UAT, and the latest Figma Cloud design.

The work was limited to read-only cloud/console inspection, reversible
accessibility and text-scale checks on the connected Vivo, synthetic or
cancelled account flows, and edits to the already-authorized Figma file. It did
not create a Play developer account, upload an AAB, select a real Google
account, change Firebase/App Check state, publish a design, enroll research
participants, or upload production research data.

## Release identity

Release candidate: `1.0.0+15`

Artifact source commit:
`3cd91c8c5f25c6ee578a7226a88b2e6ce62f3dff`

| Artifact | SHA-256 |
| --- | --- |
| `build/field-release/lexiquest-1.0.0+15.apk` | `88022344F49CCB243D95EBD4E54723FC6893F365017AA833A1C8DE722B482984` |
| `build/field-release/lexiquest-1.0.0+15.aab` | `8377C7E24F3DB54B304B7389A06F9CF18C51AD77D9B20C894402E1F6C93D75F5` |

APK/AAB certificate SHA-256:
`E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`.

## Task disposition

| Card | Result | Evidence / next boundary |
| --- | --- | --- |
| Physical Vivo baseline | **Accepted** | One physical Vivo V2041, Android 13/API 33, 1080x2408 at 440 dpi, approximately 393x876 dp, 7.45 GiB RAM, single display. This is the physical mid-tier baseline only. |
| Physical low-tier | **Not verified** | No distinct low-tier physical device was connected. Emulator resource limits cannot replace OEM/thermal/device evidence. |
| Physical high-tier | **Not verified** | No distinct high-tier physical device was connected. The Vivo is not promoted to high-tier without an approved benchmark definition. |
| Physical Fold | **Not verified** | No physical hinge/posture-capable device was connected. |
| Physical tablet | **Not verified** | No physical Android tablet was connected. |
| TalkBack service/focus smoke | **Accepted, scoped** | TalkBack service enabled temporarily; Login exposed 35 nodes, 8 clickable nodes, 12 focusable nodes and 2 focused nodes; `MainActivity` remained top-resumed and severe-log matches were 0. Original accessibility settings were restored exactly. |
| Manual TalkBack spoken order | **Not verified** | A human did not listen to and confirm every label, announcement, focus transition, or OEM speech result. The smoke result must not be presented as stakeholder accessibility UAT. |
| Physical Login UAT | **Accepted, scoped** | Blank primary submit produced both required messages; Google opened the Android chooser and Back returned `ยกเลิกรายการแล้ว`; reset modal stayed open and validated blank input. No account was selected and no real credential was used. |
| 200% text | **Accepted, portrait** | At `font_scale=2.0`, the Login remained scrollable to all CTAs with no severe-log match. The original `1.0` scale was restored. |
| Landscape | **Not verified** | Vivo remained portrait after the reversible rotation attempts. The screenshot named `landscape-locked` is evidence of the unsuccessful posture attempt, not a landscape pass. Rotation settings were restored. |
| Play Console | **External gate** | The authenticated account `petch954100@gmail.com` reaches Play Console developer-account signup. No developer account/app/track exists, so the exact AAB cannot yet be accepted by Play. Account type, fee, identity verification, and public distribution are owner decisions. |
| Production cloud | **Reviewed; rollout not accepted** | Firestore rules match source, Google provider is enabled, and Play Integrity App Check is configured. However, `app_control/field.cloudSyncEnabled=true` while Firestore App Check enforcement is `UNENFORCED`; signed `+15` has no verified valid-traffic record. No production state was changed. |
| Figma Login v15 delta | **Accepted for scoped Login flow** | Interactive Code Layer plus 12 editable native Design frames now exist in the current Cloud file; details below. Other final9/post-fix deltas outside Login were not re-certified, so the whole historical R11 section is not declared current. |

## Vivo evidence

All checks used the installed signed `+15` package and avoided real account
mutation. Severe-log matching covered Android/Flutter fatal errors, RenderFlex
overflow, database lock, ANR, SIGABRT, and SIGSEGV.

| Evidence | File |
| --- | --- |
| TalkBack service/focus smoke | `build/field-release/vivo-cycle12-v15-talkback.png` |
| 200% portrait | `build/field-release/vivo-cycle12-v15-font200-portrait.png` |
| 200% after scrolling to remaining CTAs | `build/field-release/vivo-cycle12-v15-font200-scrolled.png` |
| Rotation attempt that remained portrait | `build/field-release/vivo-cycle12-v15-font200-landscape-locked.png` |
| Blank Login validation | `build/field-release/vivo-cycle12-v15-uat-blank-validation.png` |
| Native Google chooser, no selection | `build/field-release/vivo-cycle12-v15-uat-google-chooser.png` |
| Google chooser cancellation | `build/field-release/vivo-cycle12-v15-uat-google-cancel.png` |
| Reset modal | `build/field-release/vivo-cycle12-v15-uat-reset-dialog.png` |
| Reset modal invalid state | `build/field-release/vivo-cycle12-v15-uat-reset-invalid.png` |

Post-check device state was re-read as `font_scale=1.0`,
`accessibility_enabled=0`, `enabled_accessibility_services=null`,
`accelerometer_rotation=1`, and `user_rotation=0`.

## Production-cloud snapshot

- Firebase CLI `15.24.0` and gcloud `590.0.0` were authenticated to
  `vocab-learning-app-219ef`.
- Firestore is Native mode in `nam5`.
- Deployed rules normalize to the current source hash
  `60613c...4450`; active ruleset is
  `26c7068f-48ca-4a80-8087-90882ec4195c`.
- No composite indexes or field overrides were present, and the repository has
  no `firestore.indexes.json`.
- Firestore delete protection and point-in-time recovery were disabled.
- Play Integrity uses a 3600-second TTL, requires device integrity, supports
  off-Play APKs, and knows the release certificate, but Firestore enforcement
  remains `UNENFORCED`.
- Google Sign-In was `ENABLED`; a deeper Authentication configuration read was
  stopped after a quota `429` response.
- The owner-controlled AAB passed ordinary local JAR verification. Strict JAR
  verification still returns exit 4 for self-signed/no-timestamp warnings;
  only Play Console can supply acceptance evidence for this exact hash.
- The project had no billing account at inspection time. Privacy publication,
  Data Safety, privileged account deletion, retention, and store declaration
  evidence remain external release gates.

The current combination of Cloud Sync enabled and App Check unenforced is a
production risk. Changing either side was intentionally not inferred from an
engineering request because it changes live availability and rollout
behavior.

## Figma Cloud — Login v15

Account: `petch954100@gmail.com` (`Tammakorn1910`)

File:
`https://www.figma.com/design/o9e5GYmA1gdrLC9Csxil6w/LexiQuest-%C2%B7-Master-UI-Revision-3-%C2%B7-Clickable-Prototype?node-id=112-3`

The official MCP session opened successfully, but the Starter plan refused the
first design-system operation at its tool-call limit. The bounded fallback
used the authorized browser editor in the same Cloud file.

- Code Layer node `112:3` is named
  `LQ15 · Interactive Login · Claude Sonnet 5.5`.
- Claude Sonnet 5.5 produced Make version 2; `tsc --noEmit` and `vite build`
  passed.
- Browser automation checked blank validation, Google/provider recovery,
  reset invalid/success, Guest, Registration, password visibility, dev states,
  and credential cancellation.
- Responsive checks covered widths 320, 360, 412, 600, and 1280 pixels. No
  horizontal scroll was found; primary controls stayed at least 48 pixels and
  the form remained centered with a 560-pixel maximum width.
- A 200% root-font run at width 360 had no horizontal scroll and could reach
  the footer.
- Remote fonts and external runtime requests were removed.
- Transient field/provider/snackbar state is reset at alternate-flow
  boundaries; developer controls are collapsed outside the main flow.
- Twelve captured states were extracted into native editable Design frames,
  retained Auto Layout, and were named `LQ15 · 01` through `LQ15 · 12` for
  Default, Validation, Provider error, Reset modal/validation/success,
  Snackbar return, Guest, Register, and password-visible states.

An additional duplicate Code Layer at node `112:1819` was started as a
16-flow final9 delta atlas. Figma stopped Claude with the account's daily AI
credit limit after only `index.css` and `ui.tsx` had partial changes, before
the screen implementation, build, route checks, or Make-version commit. The
layer was therefore renamed
`DRAFT · R12 Final9 Atlas · INCOMPLETE · AI quota`; it was not extracted and
is not accepted evidence. This preserves the validated Login layer while
making the incomplete attempt impossible to mistake for the current design.

`/critique` disposition for this Login delta: **40/40**, with no unresolved
P0/P1 finding. This score applies to the new Login v15 Code Layer and extracted
states, not to every older R11 screen.

## Review and release decision

- **Running processes:** none.
- **Engineering evidence:** accepted for the connected Vivo and scoped Login
  design delta.
- **Release-ready:** no.
- **Production deployment/publication:** not authorized and not performed.
- **Research production:** remains default-off/fail-closed pending ethics,
  protocol/instrument, trusted issuer/time authority, and rollout approval.

The next external evidence must come from distinct physical low/high/Fold and
tablet devices, a human TalkBack/stakeholder UAT session, a verified Play
developer account accepting the exact AAB hash, and a controlled App Check
valid-traffic/enforcement rollout with rollback evidence.
