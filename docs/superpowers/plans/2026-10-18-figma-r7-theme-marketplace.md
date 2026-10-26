# LexiQuest Figma Revision 7 · Theme Marketplace Completion Plan

## Outcome

Deliver a single-page Figma Revision 7 prototype that makes the existing reward economy discoverable and complete. Learners can see how points are earned, browse theme templates and wallpapers, preview them in context, redeem them, apply or change them, recover from insufficient balance or offline states, and return to learning without changing mastery results.

Revision 7 preserves Revision 6 as rollback evidence and keeps the frozen 8-category/44-capability catalog intact.

## Material constraints

- Android first. The canonical phone remains Vivo V2041 at 393×876dp, with the existing compact, foldable, tablet, dark, IME, and 200% text specimens retained.
- Use the real runtime contracts in `lib/features/rewards/domain/reward_models.dart`, `lib/features/rewards/domain/reward_eligibility.dart`, and `lib/screens/shop_page.dart`; do not invent a second point or ownership authority.
- Rewards are cosmetic. Theme templates, wallpapers, and avatar items must never change mastery, learning evidence, streak authority, or research records.
- All user-facing copy uses ordinary Thai. English remains only for necessary product terms and test annotations.
- The visual hierarchy adapts the task/catalog structure documented from AllTCAS, Astra's contextual disclosure, and Duolingo's visible reward loop without copying branding or protected assets.
- Figma stays in one Page. Revision 6 remains available until Revision 7 is verified.
- Claude is the design director for art direction and critique. Codex implements and verifies the resulting design in the existing generator.

## Deliverables

1. **Research and design direction**
   - Reconcile existing REA evidence, screenshots, Figma Community research, runtime reward contracts, and Claude feedback.
   - Record the selected marketplace information architecture, layout grid, typography, visual language, and plain-Thai vocabulary.

2. **Revision 7 generator**
   - Create `tmp/figma/lexiquest_master_ui_v7.js` from the verified Revision 6 source.
   - Add direct shop entry points from Home, Profile, the all-menu hub, Progress/Rewards, and Appearance.
   - Add the complete points-to-theme journey: points center, history, store, filters, item detail, full preview, redeem confirmation, success, apply, owned library, customization, wallpaper detail, insufficient balance, download state, and offline-owned state.
   - Use a consistent 20dp phone gutter, 8dp rhythm, 48dp minimum targets, aligned card grids, and deterministic focus order.

3. **Prototype graph and acceptance checks**
   - Connect every interactive node with a meaningful destination, Back, Close, or state transition.
   - Add a product flow start for the theme marketplace and QA starts for the insufficient-balance and offline-owned cases.
   - Assert the primary marketplace sequence and all entry points in the validator.
   - Keep dead interactions, broken routes, duplicate route sources, section bounds, and content bounds at zero.

4. **Preview, critique, and Figma delivery**
   - Render all Revision 7 frames and contact sheets.
   - Run Claude critique on the new marketplace and representative core screens, then apply all P0/P1 findings.
   - Build and run a Revision 7 Figma plugin in the current Page, keeping Revision 6 as rollback.
   - Smoke-test Home → Store → Detail → Preview → Redeem → Apply, the insufficient-points path, Back navigation, and direct menu entry points in the live prototype.

## Verification

- `node tmp/figma/render_master_ui_v7_preview.mjs`
- `node tmp/figma/validate_master_ui_v7.mjs`
- `node tmp/figma/build_master_ui_v7_plugin.mjs`
- `node --check` for the validator, renderer, builder, and generated plugin
- Manifest assertions: exact screen/route/start counts; 44 catalog capabilities; zero dead, broken, duplicate, section-bound, and content-bound errors
- Live Figma smoke test for the primary marketplace journey and permission/share state

## External and release boundaries

- Figma design completion does not authorize a production release or real-data migration.
- Physical-device TalkBack, hinge/posture behavior, and runtime theme application remain implementation verification after the Figma handoff.
- The old Figma invite may be removed only after action-time confirmation; the user supplied that confirmation on 2026-10-18.
