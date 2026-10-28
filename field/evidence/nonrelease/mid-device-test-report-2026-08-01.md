# LexiQuest vivo V2041 non-release device test

- Evidence class: debug/non-release; this is not P8-E release certification.
- Device: vivo V2041, Android 13 (SDK 33), 7631 MB RAM, Mali-G57 MC2.
- APK SHA-256: `1EDF3EE4FC2034C9BE9E051B77794C9ACBD43A15D8616017CBB16E82BFAD816F`.
- Install mode: `adb install -r` over the same versionCode 1 debug build. This does not prove clean install or upgrade install.
- App crash/ANR markers observed during the bounded run: 0/0.

## Results

| Check | Result | Evidence |
|---|---|---|
| Existing local vocabulary after same-version replacement | Partial | `screenshots/main-after-guest.png` shows existing `Animals`; the full offline journey was not rerun. |
| Guest process-restart persistence | Fail | Reproduced 2/2: Guest main screen before force-stop, Login screen after launcher restart. See `screenshots/guest-before-force-stop.xml` and `screenshots/guest-after-force-stop.xml`. |
| Background/resume | Partial pass | HOME then resume preserved the AI settings route and PID. Reboot was not tested. |
| Gemini BYOK configuration | Partial pass | Active secure credential state, authenticated model discovery, and atomic save were visible. No secret was captured. |
| Gemini generation | Fail | One request using `gemini / antigravity-preview-05-2026` returned the app category `invalid key/blocked`; usage recorded 1 request, 0 tokens, cost unknown. No retry was performed. |
| AI Provider settings layout | Fail | The Provider dropdown overflowed to the right by 15 pixels on this device. See `screenshots/ai-provider-settings-overflow.png`. |
| Endurance | Pending | Only a bounded smoke run was performed; the required 30-minute endurance run was not executed. |

## Release blockers discovered

1. Startup routing does not restore the active Guest owner after process death; it always returns to Login.
2. Gemini live generation did not succeed even though credential validation and model save succeeded.
3. Gemini HTTP 400, 401, and 403 responses are collapsed into one `invalidKey` category, preventing accurate diagnosis of model/request rejection versus invalid credential.
4. The Provider dropdown has a reproducible 15-pixel right overflow on vivo V2041.

The remaining journeys stay pending. Evidence from this debug APK must not be combined with a future signed release-candidate hash.
