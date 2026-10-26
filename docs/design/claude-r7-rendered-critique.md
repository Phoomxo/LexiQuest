# LexiQuest Revision 7 Marketplace Audit

## P0 Blockers
None. All critical paths are routed, states are defined, and core interactions are complete.

## P1 Issues

1. **M39 confirmation arithmetic mismatch** – "before 1,240 → after 1,160" shows an 80-point deduction, but if the user arrived from M37 (มหาสมุทรสงบ 80แต้ม), the math is correct. If they arrived from a different detail screen with a different price, the confirmation must reflect that price dynamically. Verify that M39 receives and displays the correct price for every entry path.

2. **M37 description left-alignment with multi-line Thai** – Left-aligned Thai paragraph text is correct for readability, but verify that line height is at least 1.5× cap height (roughly 24sp for 16sp body) to prevent Thai descenders and tone marks from crowding. If line height is tighter than 1.4×, increase it.

3. **M38 context labels legibility** – Three context labels on a dark full-screen preview must meet 4.5:1 contrast against both the preview image and any gradient overlay. If labels are white on a variable-brightness preview, confirm a scrim or consistent background treatment exists.

4. **M44 owned themes grid density** – If owned themes use the same 2-column cards as M35 browse, ensure vertical rhythm remains 8dp and that a user with 10+ owned themes can scroll without card overlap or clipped badge indicators.

5. **M46 points center → M47 history routing** – Confirm that M47 includes a back route to M46 (not directly to Home) so users can return to the points summary after viewing history.

6. **M50 offline-owned static messaging** – "stale catalog" and "offline-owned" are distinct states. Confirm that M50 shows owned themes with full preview capability even offline, and that only browse/redeem are disabled with clear messaging (e.g., "ต้องเชื่อมต่ออินเทอร์เน็ต" for locked sections).

## Dimension Scores (0–10)

| Dimension | Score | Notes |
|-----------|-------|-------|
| **Discovery** | 8 | Direct routes from Home, Profile, Progress, All menus. Visible balance card. Points history discoverable. Docked 2 for lack of entry-point priority signal (Home card could use higher elevation or color to differentiate from content cards). |
| **Hierarchy & Alignment** | 9 | 20dp gutters, 8dp rhythm, 48dp targets, 2-column grids, left-aligned Thai prose. Deducted 1 pending line-height verification for M37. |
| **Thai Readability** | 9 | Plain vocabulary (ร้านธีม, แลก, เป็นเจ้าของแล้ว, กำลังใช้). Noto Sans Thai. Readable ink on canvas. Deducted 1 pending M37 line-height confirmation. |
| **Accessibility** | 8 | 48dp targets, assumed semantic labels. Deducted 2 for M38 contrast uncertainty and lack of explicit focus-order documentation for multi-card scrollable grids. |
| **Purchase Clarity** | 9 | Balance visible, preview before redeem, confirmation with arithmetic, cosmetic-only notice, success/failure states. Deducted 1 for M39 arithmetic verification gap. |
| **Brand Distinctiveness** | 8 | Original geometric theme art, market coral, amber points, mastery teal. Clear separation from mastery UI. Deducted 2 for not explicitly confirming that market coral is reserved exclusively for marketplace (if it appears elsewhere, distinctiveness weakens). |
| **Route & State Completeness** | 10 | 16 screens, all entry/exit/error/offline/owned states mapped. Zero dead ends. Back uses prototype BACK. Success. |

## Verdict

**CONDITIONAL PASS** – pending verification of:
- M39 arithmetic correctness for all entry paths
- M37 Thai line height ≥ 1.5×
- M38 label contrast ≥ 4.5:1 against all preview backgrounds
- M50 owned-theme offline preview capability

If all four verifications pass, **FULL PASS**. All dimensions meet or exceed 7/10. No P0 blockers exist. This is a complete, routed, accessible, culturally appropriate marketplace experience ready for user testing.
