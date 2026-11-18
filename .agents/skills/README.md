# LexiQuest Agent Skills Catalog & Categorized Taxonomy

This directory contains the operational skills for all AI agents working on LexiQuest.
Skills are organized into functional suites to eliminate fragmentation.

---

## 🎨 Suite 1: UI/UX & Design System Suite (`ui-design-suite`)
Everything related to visual presentation, design tokens, responsiveness, and anti-slop craft:
- **`ui-design-suite`**: Master coordinator for all UI design skills.
- **`figma-designer`**: Extraction of Design Tokens, typography scales, spacing, and styles from Figma.
- **`taste-skill` (`design-taste-frontend`)**: Anti-slop frontend aesthetic gate (visual balance, bespoke typography, micro-interactions).
- **`ui-ux-pro-max`**: Professional mobile & desktop UI guidelines, palette generation, and UX rules.
- **`landing-page-design`**: Page hierarchy, layout structures, and conversion copy.
- **`flutter-build-responsive-layout`**: Responsive layout patterns (`LayoutBuilder`, `MediaQuery`, Material 3 Compact).
- **`flutter-fix-layout-issues`**: Automated resolution of RenderFlex overflows and unbounded constraints.
- **`flutter-add-widget-preview`**: Interactive component widget previews.

---

## 🏗️ Suite 2: Architecture, Logic & Database Suite
Everything related to Clean Architecture, state management, and Drift SQLite:
- **`flutter-apply-architecture-best-practices`**: Enforces 4-layer separation (UI $\rightarrow$ Bloc $\rightarrow$ Repo $\rightarrow$ Drift).
- **`flutter-setup-declarative-routing`**: Declarative routing with deep link and state parameters.
- **`flutter-setup-localization`**: Multi-language (Thai/English) localization setups.
- **`flutter-implement-json-serialization`**: Safe serialization/deserialization.
- **`flutter-use-http-package`**: REST API client interactions.
- **`dart-use-pattern-matching`**: Dart 3 pattern matching, exhaustive switches, and destructuring.
- **`dart-use-primary-constructors`**: Idiomatic Dart 3 concise constructor syntax.
- **`dart-build-cli-app`**: CLI tools and background daemon architecture.
- **`dart-setup-ffi-assets`** & **`dart-use-ffigen`**: C/C++ native assets and bindings.

---

## 🧪 Suite 3: Verification, QA & Testing Suite
Everything related to proving correctness before claiming completion:
- **`flutter-add-widget-test`**: Component test using `WidgetTester` (simulates tap, scroll, text entry).
- **`flutter-add-integration-test`**: Full flow tests driving the app headlessly.
- **`dart-add-unit-test`**: Unit tests for business logic and use cases.
- **`dart-generate-test-mocks`**: Mock dependencies via `package:mockito`.
- **`dart-collect-coverage`**: Code coverage tracking (LCOV).
- **`dart-run-static-analysis`**: Static linting and automated fixes (`dart fix`).
- **`verification-before-completion`**: Mandatory check requiring executable evidence before claiming done.
- **`code-review-and-quality`**: Multi-axis code review.
- **`debugging-and-error-recovery`**: Systematic root-cause debugging.

---

## 🛡️ Suite 4: Project Quality Constraints & Governance Suite
Everything related to preventing code regressions and low-quality output:
- **`constraint-driven-development`**: Prevents agents from lowering quality bars, writing stubs, or silencing checks.
- **`using-agent-skills`**: Meta-skill for discovering and orchestrating other skills.
- **`performance-optimization`**: Profiling, N+1 query elimination, and rendering optimization.
- **`security-and-hardening`**: Local storage protection, cryptographic verification, and credential protection.
