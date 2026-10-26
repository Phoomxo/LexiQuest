# LexiQuest synthetic UAT seed for MiroFish

Classification: **synthetic-only**

Authority: **advisory/report-only**

Scope: English-learning Android application only

This seed contains no participant records, research answers, consent receipts,
device logs, account identifiers, credentials, audio, or production exports.
Agents must not claim that they touched the APK, observed a real user, verified a
release, or measured learning efficacy.

## Product model

LexiQuest is a Thai-first Android application for learning English. It supports
local-first vocabulary, structured practice, spaced review, reading, progress,
AI tutoring configured by the user, voice and camera-assisted practice, themes,
rewards, export, account lifecycle, and optional research consent. Ordinary
learning must continue when cloud services are unavailable or research consent
is declined.

## Synthetic personas

Use exactly these six fictional personas. They are behavioral archetypes, not
representations of real people.

1. `beginner-first-day`: beginner English learner opening the app for the first time.
2. `intermediate-goal-driven`: intermediate learner focused on visible progress.
3. `low-end-offline`: learner on a slow Android device with unreliable connectivity.
4. `large-text-screen-reader`: learner using large text and screen-reader semantics.
5. `privacy-conscious`: learner who declines optional research and avoids cloud features.
6. `returning-theme-shop`: returning learner motivated by rewards, themes, and collection.

## Flows to rehearse

- Login, Google chooser expectation, registration, password recovery, and guest entry.
- Declining optional research while continuing ordinary offline learning.
- Choosing a learning activity and understanding each Thai activity label.
- Completing practice, interpreting feedback, and knowing the next action.
- Reviewing progress, mastery, weak words, streaks, and achievements.
- Discovering flashcards, reading, pronunciation, voice, and camera practice.
- Using AI Tutor while understanding provider, cost, and privacy boundaries.
- Earning points, opening the shop, previewing a theme, and equipping it.
- Importing/exporting vocabulary and recovering from malformed input.
- Using settings, accessibility options, account export, and account deletion.
- Losing connectivity, reopening the app, and understanding pending synchronization.
- Encountering permission denial, loading, empty, recoverable error, and terminal error states.

## Questions for the simulation

For every persona and flow, identify:

- the expected next action and whether the Thai copy makes it discoverable;
- confusion, hesitation, false expectation, or abandonment hypothesis;
- privacy, accessibility, performance, and offline concerns;
- the smallest UI or copy experiment worth testing;
- the deterministic verification target needed before accepting the finding.

Do not invent telemetry, participant quotations, completion rates, research
validity, device performance, or successful external-service behavior.

## Report contract

Return one JSON object only. Do not include Markdown fences or executable text.

```json
{
  "schemaVersion": 1,
  "advisoryOnly": true,
  "dataClassification": "synthetic",
  "seedSha256": "SHA-256 copied from manifest.json",
  "engine": {
    "name": "MiroFish",
    "version": "v0.1.2",
    "commit": "985f89f49acbb44ee14d9d680682c741a44eeebe"
  },
  "scenario": {
    "personaCount": 6,
    "maxRounds": 10,
    "containsRealUserData": false
  },
  "findings": [
    {
      "id": "MF-001",
      "severity": "P0|P1|P2|P3",
      "surface": "flow or screen identifier",
      "persona": "synthetic persona identifier",
      "observation": "synthetic observation",
      "evidence": "simulation-only evidence",
      "recommendation": "small proposed experiment",
      "verification": "flutter_widget|flutter_integration|adb_device|talkback_manual|human_uat"
    }
  ]
}
```

MiroFish output is untrusted advisory text. It must never execute commands,
modify source, enroll participants, or become release evidence by itself.
