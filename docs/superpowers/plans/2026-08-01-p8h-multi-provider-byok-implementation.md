# LexiQuest P8-H Multi-Provider BYOK Implementation Plan

**Status:** READY FOR EXECUTION

**Scope:** Extend the AI Tutor so each participant can choose their own AI
provider (Gemini, OpenAI, OpenRouter, Claude, or a custom OpenAI-compatible
endpoint such as a Thai provider) and enter their own API key and model name.

**Out of scope:** Backend proxy, multi-key fallback chain, and Thai provider
adapters with non-OpenAI formats (those are added later once the owner supplies
the format). A custom OpenAI-compatible slot covers most Thai providers today.

**Upstream:** P8-D through `e393b8c`.

## Delivery rules

- Device-direct only; no backend dependency for the tutor.
- Each provider has its own gateway adapter. Adding a provider is an adapter
  change, never a change to the tutor UI or use cases.
- API keys are never logged, persisted insecurely, or included in exceptions.
- The existing Gemini gateway is preserved; participants who already have a
  Gemini key keep working after migration.
- A participant selects exactly one provider + model + key at a time.

## Dependency order + tasks

H1 contracts → H2 OpenAI adapter → H3 Claude adapter → H4 settings store →
H5 gateway factory → H6 use cases + bootstrap → H7 settings UI → H8 gate.

See the approved plan for per-task file lists and commits.
