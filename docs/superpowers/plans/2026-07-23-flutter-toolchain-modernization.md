# Flutter Toolchain Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LexiQuest reproducibly buildable with the current stable Flutter 3.44.7, Dart 3.12.2, Android API 36, and current direct Dart packages as of 2026-07-23.

**Architecture:** Keep application behavior unchanged while modernizing only the SDK constraints, dependency graph, and generated Android build toolchain. Use the versions emitted by the installed Flutter 3.44.7 project template for AGP, Kotlin, Gradle, Java, compile SDK, target SDK, and minimum SDK.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, Android Gradle Plugin 9.0.1, Kotlin Gradle Plugin 2.3.20, Gradle 9.1.0, JDK 21 runtime with Java 17 bytecode, Firebase, Supabase.

## Global Constraints

- Keep the existing branch name `feature/omnivoice-integration`; do not introduce a `codex/` branch prefix.
- Do not change Firebase or Supabase project identifiers, credentials, application data, or user-facing behavior.
- Keep OmniVoice research dependencies in the locked `gpu` dependency group in `backend/voice_api/pyproject.toml` and `backend/voice_api/uv.lock`.
- Treat the existing 188 analyzer warnings/info messages as baseline debt; this migration must introduce zero analyzer errors.
- Do not commit `android/local.properties`, `.env`, service-account JSON, model weights, generated audio, or Hugging Face cache files.

---

### Task 0: Replace the stale template test with a real login smoke test

**Files:**
- Modify: `test/widget_test.dart`
- Modify: `lib/screens/LoginScreen.dart`

**Interfaces:**
- Consumes: the real `LoginScreen` widget and the existing `AuthService`.
- Produces: a network-free widget test that verifies the production login form, with Firebase construction deferred until login is attempted.

- [ ] **Step 1: Write the failing production-widget test**

Replace the Counter template test with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/LoginScreen.dart';

void main() {
  testWidgets('login screen renders its credentials form', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(find.text('Login'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.text('Don’t have an account? Register here'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Verify the new test fails for the diagnosed reason**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: FAIL with `[core/no-app]` because `_LoginScreenState` eagerly initializes `AuthService`.

- [ ] **Step 3: Defer Firebase access until a login attempt**

In `_LoginScreenState`, replace the eager field with:

```dart
AuthService? _authService;

AuthService get _auth => _authService ??= AuthService();
```

Use `_auth.signIn(...)` inside `_login()`. Add `dispose()` for both text controllers:

```dart
@override
void dispose() {
  _emailController.dispose();
  _passwordController.dispose();
  super.dispose();
}
```

- [ ] **Step 4: Verify the root-cause fix**

Run:

```powershell
flutter test test/widget_test.dart
```

Expected: PASS while exercising the real `LoginScreen` without network or Firebase initialization.

### Task 1: Modernize Dart SDK and direct dependencies

**Files:**
- Modify: `pubspec.yaml`
- Regenerate: `pubspec.lock`

**Interfaces:**
- Consumes: Flutter 3.44.7 and Dart 3.12.2 installed on the workstation.
- Produces: A dependency graph resolvable on Dart `>=3.12.0 <4.0.0`.

- [ ] **Step 1: Record the pre-migration dependency and analyzer baseline**

Run:

```powershell
dart pub outdated --json
dart analyze
```

Expected: direct packages report the resolvable versions listed below; analysis reports no errors and 188 existing warnings/info messages.

- [ ] **Step 2: Update SDK and package constraints**

Set `environment.sdk` to `'>=3.12.0 <4.0.0'` and use these direct constraints:

```yaml
cupertino_icons: ^1.0.9
firebase_core: ^4.12.1
firebase_auth: ^6.5.6
firebase_storage: ^13.4.5
provider: ^6.1.5+1
cloud_firestore: ^6.7.1
google_fonts: ^8.2.0
speech_to_text: ^7.4.0
flutter_tts: ^4.2.5
image_picker: ^1.2.3
fl_chart: ^1.2.0
http: ^1.6.0
supabase_flutter: ^2.16.0
shared_preferences: ^2.5.5
file_picker: ^11.0.2
fluttertoast: ^9.1.0
confetti: ^0.8.0
cached_network_image: ^3.4.1
flutter_speed_dial: ^7.0.0
mailer: ^7.2.0
flutter_lints: ^6.0.0
```

- [ ] **Step 3: Resolve and lock the new graph**

Run:

```powershell
dart pub upgrade
```

Expected: dependency solving succeeds and `pubspec.lock` records Dart 3-compatible package versions.

- [ ] **Step 4: Verify compile compatibility**

Run:

```powershell
dart analyze
```

Expected: zero analyzer errors. Existing warnings/info may remain and are counted separately.

### Task 2: Modernize the Android build toolchain

**Files:**
- Modify: `android/settings.gradle`
- Modify: `android/app/build.gradle`
- Modify: `android/build.gradle`
- Modify: `android/gradle/wrapper/gradle-wrapper.properties`
- Generate: `android/gradlew`
- Generate: `android/gradlew.bat`
- Generate: `android/gradle/wrapper/gradle-wrapper.jar`
- Generate locally only: `android/local.properties`

**Interfaces:**
- Consumes: Android SDK API 36, Build Tools 36.1.0, JDK 21, and Flutter SDK path.
- Produces: A Gradle 9.1.0 wrapper configured for AGP 9.0.1 and Kotlin 2.3.20.

- [ ] **Step 1: Write local SDK paths**

Create ignored `android/local.properties` with:

```properties
sdk.dir=C:\\Users\\Phet\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\Users\\Phet\\AppData\\Local\\Programs\\flutter
```

- [ ] **Step 2: Align plugin versions to the Flutter 3.44.7 template**

Use these versions in `android/settings.gradle`:

```groovy
id "com.android.application" version "9.0.1" apply false
id "org.jetbrains.kotlin.android" version "2.3.20" apply false
id "com.google.gms.google-services" version "4.5.0" apply false
```

Remove the duplicate Google Services plugin declaration from `android/build.gradle`.

- [ ] **Step 3: Align Android language and SDK defaults**

In `android/app/build.gradle`, compile Java/Kotlin to JVM 17 and use:

```groovy
minSdk = flutter.minSdkVersion
targetSdk = flutter.targetSdkVersion
```

Flutter 3.44.7 resolves these values to min SDK 24, target SDK 36, compile SDK 36, and NDK `28.2.13676358`.

- [ ] **Step 4: Generate the current Gradle wrapper**

Run the Gradle wrapper task with Gradle 9.1.0 and distribution type `all`.

Expected: wrapper scripts and `gradle-wrapper.jar` are present, and the distribution URL is:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.1.0-all.zip
```

- [ ] **Step 5: Verify Gradle configuration**

Run:

```powershell
android\gradlew.bat --version
android\gradlew.bat :app:tasks
```

Expected: Gradle 9.1.0 starts on JDK 21 and configures the Android app without plugin-version errors.

### Task 3: Verify application behavior and platform builds

**Files:**
- Test: `test/widget_test.dart`
- Test: existing files under `test/`

**Interfaces:**
- Consumes: the modernized Dart and Android dependency graphs.
- Produces: verified Flutter tests plus Android and Web build evidence.

- [ ] **Step 1: Enable Windows Developer Mode**

Set `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense=1` from an elevated Windows session.

Expected: Flutter can create plugin symlinks without the “Building with plugins requires symlink support” failure.

- [ ] **Step 2: Resolve Flutter plugins**

Run:

```powershell
flutter pub get
```

Expected: package resolution and plugin symlink generation both succeed.

- [ ] **Step 3: Run regression tests**

Run:

```powershell
flutter test
```

Expected: all existing tests pass. Any behavior regression must first receive a failing test reproducing it before production code changes.

- [ ] **Step 4: Modernize APIs surfaced by the new SDK and packages**

Replace API calls deprecated by Flutter 3.44.7 or the upgraded direct dependencies, including:

```dart
color.withOpacity(alpha)
```

with:

```dart
color.withValues(alpha: alpha)
```

Replace legacy drag callbacks with `onAcceptWithDetails` / `onWillAcceptWithDetails`, and replace legacy `speech_to_text` listen parameters with `SpeechListenOptions`. Preserve the existing interaction behavior and add a failing focused test first whenever a behavior change is required.

- [ ] **Step 5: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: zero errors. Compare warning/info count with the recorded 188-message baseline.

- [ ] **Step 6: Build supported targets**

Run:

```powershell
flutter build apk --debug
flutter build web
```

Expected: a debug APK and Web bundle are produced without toolchain or dependency errors.

### Task 4: Verify OmniVoice and external CLIs

**Files:**
- No tracked source files changed.

**Interfaces:**
- Consumes: the pinned Python 3.11 virtual environment and model revision `c5fdb5ccb189668d56333f77ba2629f4cd7535f4`.
- Produces: version, GPU, test, model-cache, and CLI verification evidence.

- [ ] **Step 1: Verify the voice runtime**

Run:

```powershell
backend\voice_api\.venv\Scripts\python.exe -c "import torch, torchaudio, omnivoice; print(torch.__version__, torchaudio.__version__, torch.cuda.is_available())"
```

Expected: PyTorch and torchaudio `2.8.0+cu128`, OmniVoice `0.2.1`, and CUDA `True`.

- [ ] **Step 2: Verify the pinned model snapshot**

Call `huggingface_hub.snapshot_download` with the locked model ID and revision.

Expected: the command returns a local snapshot directory without downloading a different revision.

- [ ] **Step 3: Run backend tests**

Run:

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -v
```

Expected: all voice API unit tests pass without requiring Firebase credentials or model inference.

- [ ] **Step 4: Verify CLIs and Docker**

Run:

```powershell
ffmpeg -version
firebase --version
supabase --version
docker info
```

Expected: FFmpeg 8.1.2, Firebase CLI 15.24.0, Supabase CLI 2.109.1, and a reachable Docker Desktop daemon.
