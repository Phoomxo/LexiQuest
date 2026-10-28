# CEFR catalog UI organization

User requested UI cleanup after R9 editorial delivery because information looks
crowded, authorizing AllTCAS-style organization. Apply existing Material 3 and
Thai accessibility patterns; no new branding assets or domain behavior.
R9 device screenshots are the baseline. Existing AllTCAS UI acceptance delta
supports structured catalogs/lexical detail; no external live UI replication.

Design: catalog overview card, separate search/filter panel, spaced word cards.
All body content scrolls on narrow screens/with keyboard. Word details use a
full page: headword and level/POS, meaning card, English example block, Thai
translation block, AI-review label, expandable dictionary alternatives and
level/source explanation. Keep primary import action outside scrolling content.
Reading library receives matching section headings and spaced level cards.
Alternatives considered: spacing-only dialog preserves its cramped width;
bottom sheet still constrains long content; full detail page is selected.

No data, source keys, import semantics, permissions, feature flags or vocabulary
asset changes. Existing route entry remains. Reader now pushes a child page so
Back returns to the library; an existing replacement-page bug was exposed by
review and a RED A1 → Back → A2 test. Tests cover navigation/import and
large text; add short-viewport keyboard regression to expose current overflow.

- [x] Reproduce short-viewport overflow; implement catalog/detail organization.
- [x] Organize reading library and run relevant widget/encoding/import checks.
- [x] Analyze, build source-pinned R10 previews, hash-safe vivo update.
- [x] Inspect before/after screenshots and persistence; final checkpoint.
