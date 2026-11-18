---
name: ui-design-suite
description: >-
  Master UI/UX Design System Suite for LexiQuest. Unifies and orchestrates all AI design skills:
  figma-designer (tokens, styles, auto-layout), taste-skill (anti-slop aesthetics, typography, micro-interactions),
  ui-ux-pro-max (professional UI design intelligence, color palette, responsive design),
  landing-page-design, flutter-build-responsive-layout, and flutter-fix-layout-issues.
  Use whenever designing, building, restyling, or reviewing any UI screen, widget, or layout.
---

# LexiQuest UI/UX Design System Suite (Unified AI Design Suite)

Master coordinator for all UI design skills across OpenAI Codex, Anthropic Claude, Google Gemini/Antigravity, and Cursor.

## Integrated Skill Members

| Sub-Skill | Role & Purpose | Tool / Location |
|---|---|---|
| **`figma-designer`** | Extracts Design Tokens (colors, typography, spacing, radius) and auto-layouts from Figma | `.agents/skills/figma-designer` |
| **`taste-skill`** | Eliminates AI slop; enforces negative space, visual balance, and bespoke typography | `.agents/skills/taste-skill` |
| **`ui-ux-pro-max`** | Comprehensive mobile & desktop design guidelines, color psychology, and platform rules | `.agents/skills/ui-ux-pro-max` |
| **`flutter-build-responsive-layout`** | Ensures adaptive rendering across mobile (Vivo Y21 baseline <600dp), foldable, and tablet | `.agents/skills/flutter-build-responsive-layout` |
| **`flutter-fix-layout-issues`** | Detects and resolves RenderFlex overflow (yellow/black tape) and unbounded constraints | `.agents/skills/flutter-fix-layout-issues` |
| **`landing-page-design`** | Landing page and presentation structure, conversion typography, and web presentation | `.agents/skills/landing-page-design` |

## Execution Workflow (Mandatory 4-Step UI Pipeline)

1. **Step 1: Tokens & Figma Foundation (`figma-designer`)**
   - Check Figma variables, color palette, and spacing scale (8dp grid).
   - Ensure color definitions map directly to `lib/config/m3_theme.dart`.

2. **Step 2: Platform Architecture & Responsiveness (`ui-ux-pro-max` + `flutter-build-responsive-layout`)**
   - Baseline viewport: Android Material 3 Compact (<600dp width).
   - Use `LayoutBuilder`, `MediaQuery`, or `Expanded/Flexible` to prevent fixed-pixel clipping.

3. **Step 3: Aesthetic & Anti-Slop Polish (`taste-skill`)**
   - Equal left/right content margins.
   - Clean typographic hierarchy (maximum 3 font sizes per screen).
   - Meaningful micro-interactions on button press/card hover.
   - 0 dummy buttons (`onPressed: () {}` is strictly forbidden).

4. **Step 4: Layout & Interactive Verification (`flutter-fix-layout-issues` + `flutter-add-widget-test`)**
   - Verify 0 RenderFlex overflow warnings during execution.
   - Write a widget test simulating tap and verifying state change.
