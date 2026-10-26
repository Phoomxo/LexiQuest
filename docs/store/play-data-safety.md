# Play Data Safety worksheet

Status: engineering worksheet; owner approval and Play Console submission are external gates.

## Current Android data flow

| Data | Default behavior | Purpose | Release declaration |
| --- | --- | --- | --- |
| Email and Firebase UID | Collected only after account sign-in | Authentication, owner isolation, optional sync | Account management |
| Vocabulary and learning activity | Stored locally; supported records sync only when Cloud is enabled | Core learning, progress and review scheduling | App functionality |
| Camera image and recognized text | Used only after an explicit scanner action; raw image is not research data by default | Vocabulary capture | App functionality |
| Microphone and recognized speech | Used only after explicit practice; the current recognizer sets `onDevice: false`, so the Android/platform speech provider may process audio or recognized text over the network | Pronunciation practice | App functionality and platform-provider processing |
| Gemini prompt and response | Sent only after BYOK setup and explicit activation | AI tutoring | App functionality; third-party processing disclosed |
| Device/runtime diagnostics | Bounded technical status and explicit support evidence | Reliability and compatibility | App functionality |
| Research records | No production collection or upload while research authority is unavailable | Optional approved study only | Excluded from ordinary release while default-off |

No advertising SDK or cross-app tracking authority is present in the current dependency inventory. The Supabase client is initialization-only and has no runtime data caller; marketplace behavior remains local-only even when `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY` is present. Firebase remains the account and structured-data authority.

## Required Console answers

- Data is encrypted in transit.
- Users can request account deletion in the app and from the approved external deletion URL.
- Reconcile every answer against the final dependency/data-flow inventory before submission.
- Camera, microphone, Gemini and Cloud features are optional.
- Do not declare speech recognition as offline-only; reconcile the selected Android speech provider and its disclosure for the final device/build.
- Research remains excluded until a separately approved study release has current ethics, consent and deletion evidence.

Do not submit this worksheet until the release verifier accepts an owner-supplied contact configuration and the production account-deletion journey passes.
