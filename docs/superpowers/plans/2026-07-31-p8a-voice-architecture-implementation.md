# P8-A Voice Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OmniVoice-specific runtime spine with one provider-neutral
voice orchestrator that preserves current behavior and can accept offline
packs, VoxCPM standard speech, and session-only VoxCPM voice mirroring without
changing learning screens.

**Architecture:** Keep `VoiceProvider` as the presentation-facing façade.
Route each validated `VoiceRequest` through a pure policy resolver and a typed
provider registry. Native TTS, offline assets, OmniVoice, and future VoxCPM
providers become route handlers; the orchestrator owns fallback, cancellation,
telemetry, and lifecycle.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, `flutter_tts`, `audioplayers`,
`package:http`, Firebase ID tokens, Flutter unit/widget tests, PowerShell 5.1
CLI gates.

## Global Constraints

- Drift remains the runtime source of truth; this package adds no database
  table and no Firebase voice payload.
- Screens depend only on `VoiceProvider` and the application dependency scope.
- VoxCPM model code and model weights are not added in P8-A.
- Native TTS remains the safe fallback when remote voice is unavailable.
- Participant voice data is never cached by the standard audio cache.
- Telemetry excludes spoken text, voice IDs, authorization, raw audio, and
  participant voiceprints.
- Existing P0-P7 behavior and the exact field APK evidence remain historical;
  P8-A produces a new APK hash only after the package gate passes.
- GLM and the Cointh provider are not used.
- Preserve unrelated generated plugin files and untracked `AGENTS.md`.
- Stop on retry loops, repeated filesystem errors, or ten minutes without
  measurable progress.

## File Structure

### New domain and application files

- `lib/voice/voice_capability.dart` — capability and privacy-scope enums.
- `lib/voice/voice_provider_descriptor.dart` — immutable provider metadata.
- `lib/voice/voice_provider_registry.dart` — typed engine-to-handler registry.
- `lib/voice/voice_policy.dart` — pure route context, plan, source, and resolver.
- `lib/voice/voice_synthesis_provider.dart` — provider-neutral WAV result and
  synthesis port.
- `lib/voice/voice_route_handler.dart` — cancellation token and route-handler
  contract.
- `lib/voice/native_voice_route_handler.dart` — Native TTS route.
- `lib/voice/synthesized_voice_route_handler.dart` — cached synthesis/playback
  route.
- `lib/voice/voice_orchestrator.dart` — façade implementation.
- `lib/voice/bundled_voice_asset_provider.dart` — provider-neutral bundled
  offline asset adapter.
- `lib/runtime/scoped_voice_provider.dart` — resolves an injected or
  application-scoped provider for presentation.

### Files replaced or removed

- Remove `lib/voice/hybrid_voice_service.dart` after the orchestrator tests pass.
- Remove `lib/voice/omni_voice_asset_provider.dart` after callers use
  `BundledVoiceAssetProvider`.
- Keep `lib/voice/omni_voice_provider.dart`, but make it implement the generic
  synthesis port.

### Existing files modified

- `lib/voice/voice_models.dart`
- `lib/voice/voice_audio_cache.dart`
- `lib/voice/voice_telemetry.dart`
- `lib/voice/voice_service_factory.dart`
- `lib/runtime/app_dependencies.dart`
- `lib/runtime/app_bootstrap.dart`
- participant screens currently constructing `VoiceServiceFactory` directly
- voice, runtime, architecture, and affected screen tests
- `tool/cli/verify-voice-architecture.ps1`
- `tool/cli/tests/verify-voice-architecture.tests.ps1`

---

### Task 1: Freeze capability, engine, privacy, and failure contracts

**Files:**

- Create: `lib/voice/voice_capability.dart`
- Create: `lib/voice/voice_provider_descriptor.dart`
- Modify: `lib/voice/voice_models.dart`
- Test: `test/voice/voice_models_test.dart`
- Test: `test/voice/voice_provider_descriptor_test.dart`

**Interfaces:**

- Produces:
  - `VoiceCapability`
  - `VoicePrivacyScope`
  - `VoiceProviderDescriptor`
  - expanded `VoiceEngine`
  - expanded `VoiceFailureCategory`
  - `VoiceRequest.capability`
  - `VoiceRequest.privacyScope`

- [ ] **Step 1: Write failing contract tests**

Add tests that require the exact engine and capability sets and reject an
invalid descriptor:

```dart
test('voice contracts expose every approved P8 engine and capability', () {
  expect(VoiceEngine.values, <VoiceEngine>[
    VoiceEngine.nativeTts,
    VoiceEngine.offlinePack,
    VoiceEngine.omniVoice,
    VoiceEngine.voxCpmStandard,
    VoiceEngine.voxCpmMirror,
  ]);
  expect(VoiceCapability.values, <VoiceCapability>[
    VoiceCapability.standardTargetSpeech,
    VoiceCapability.dynamicTargetSpeech,
    VoiceCapability.sessionVoiceMirror,
    VoiceCapability.speechToText,
    VoiceCapability.pronunciationEvidence,
  ]);
});

test('participant transient descriptor cannot declare persistent caching', () {
  expect(
    () => VoiceProviderDescriptor(
      engine: VoiceEngine.voxCpmMirror,
      capabilities: const {VoiceCapability.sessionVoiceMirror},
      privacyScope: VoicePrivacyScope.participantTransient,
      allowsStandardCache: true,
    ),
    throwsArgumentError,
  );
});
```

- [ ] **Step 2: Run the tests and confirm the missing-contract failure**

Run:

```powershell
flutter test `
  test/voice/voice_models_test.dart `
  test/voice/voice_provider_descriptor_test.dart `
  --reporter compact
```

Expected: FAIL because the new enums and descriptor do not exist.

- [ ] **Step 3: Add the domain contracts**

Create `voice_capability.dart`:

```dart
enum VoiceCapability {
  standardTargetSpeech,
  dynamicTargetSpeech,
  sessionVoiceMirror,
  speechToText,
  pronunciationEvidence,
}

extension VoiceCapabilityKind on VoiceCapability {
  bool get isSpeechSynthesis => switch (this) {
    VoiceCapability.standardTargetSpeech ||
    VoiceCapability.dynamicTargetSpeech ||
    VoiceCapability.sessionVoiceMirror => true,
    VoiceCapability.speechToText ||
    VoiceCapability.pronunciationEvidence => false,
  };
}

enum VoicePrivacyScope { standardContent, participantTransient }
```

Create `voice_provider_descriptor.dart`:

```dart
import 'voice_capability.dart';
import 'voice_models.dart';

final class VoiceProviderDescriptor {
  VoiceProviderDescriptor({
    required this.engine,
    required Set<VoiceCapability> capabilities,
    required this.privacyScope,
    required this.allowsStandardCache,
  }) : capabilities = Set<VoiceCapability>.unmodifiable(capabilities) {
    if (capabilities.isEmpty) {
      throw ArgumentError.value(capabilities, 'capabilities', 'must not be empty');
    }
    if (privacyScope == VoicePrivacyScope.participantTransient &&
        allowsStandardCache) {
      throw ArgumentError(
        'Participant-transient providers cannot use standard caching.',
      );
    }
  }

  final VoiceEngine engine;
  final Set<VoiceCapability> capabilities;
  final VoicePrivacyScope privacyScope;
  final bool allowsStandardCache;

  bool supports(VoiceCapability capability) => capabilities.contains(capability);
}
```

Expand `voice_models.dart`:

```dart
enum VoiceEngine {
  nativeTts,
  offlinePack,
  omniVoice,
  voxCpmStandard,
  voxCpmMirror,
}

enum VoiceFailureCategory {
  validation,
  authentication,
  consentMissing,
  network,
  timeout,
  rateLimited,
  providerDisabled,
  modelUnavailable,
  unsupportedCapability,
  insufficientStorage,
  checksumMismatch,
  sessionExpired,
  synthesis,
  playback,
  cleanupIncomplete,
  cancelled,
  configuration,
  unknown,
}
```

Add `capability` and `privacyScope` to `VoiceRequest`, defaulting existing
callers to standard content:

```dart
VoiceCapability capability = VoiceCapability.standardTargetSpeech,
VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
```

Reject `sessionVoiceMirror` unless its privacy scope is
`participantTransient`, and reject all other synthesis requests that claim a
transient participant scope. `VoiceRequest.create` also rejects
`speechToText` and `pronunciationEvidence`; those capabilities are declared for
registry completeness but use their existing non-synthesis application ports.

- [ ] **Step 4: Run focused domain tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- `
  lib/voice/voice_capability.dart `
  lib/voice/voice_provider_descriptor.dart `
  lib/voice/voice_models.dart `
  test/voice/voice_models_test.dart `
  test/voice/voice_provider_descriptor_test.dart
git commit -m "feat(voice): define provider-neutral capability contracts"
```

### Task 2: Add the pure provider registry and routing policy

**Files:**

- Create: `lib/voice/voice_provider_registry.dart`
- Create: `lib/voice/voice_policy.dart`
- Test: `test/voice/voice_provider_registry_test.dart`
- Test: `test/voice/voice_policy_test.dart`

**Interfaces:**

- Consumes:
  - `VoiceEngine`
  - `VoiceCapability`
  - `VoicePrivacyScope`
  - `VoiceRequest`
- Produces:
  - `VoiceProviderRegistry<T>`
  - `VoiceRouteContext`
  - `VoiceRoutePlan`
  - `VoicePolicySource`
  - `StaticVoicePolicySource`
  - `VoicePolicyResolver.resolve`

- [ ] **Step 1: Write failing registry and routing tests**

Cover duplicate registration, immutable engine exposure, offline standard
speech, online dynamic speech, strict research assignment, missing mirror
consent, and mirror fallback:

```dart
test('offline standard speech uses pack then native', () {
  final plan = const VoicePolicyResolver().resolve(
    request: standardRequest,
    context: const VoiceRouteContext(
      isOnline: false,
      remoteStandardEnabled: true,
      offlinePackAvailable: true,
      voiceMirrorEnabled: false,
      hasVoiceMirrorConsent: false,
      hasActiveVoiceMirrorSession: false,
    ),
    registeredEngines: const {
      VoiceEngine.offlinePack,
      VoiceEngine.nativeTts,
    },
  );
  expect(
    plan.engines,
    const [VoiceEngine.offlinePack, VoiceEngine.nativeTts],
  );
});

test('mirror without consent fails before provider lookup', () {
  expect(
    () => const VoicePolicyResolver().resolve(
      request: mirrorRequest,
      context: onlineContextWithoutConsent,
      registeredEngines: const {VoiceEngine.voxCpmMirror},
    ),
    throwsA(
      isA<VoiceFailure>().having(
        (failure) => failure.category,
        'category',
        VoiceFailureCategory.consentMissing,
      ),
    ),
  );
});
```

- [ ] **Step 2: Run tests and confirm failure**

```powershell
flutter test `
  test/voice/voice_provider_registry_test.dart `
  test/voice/voice_policy_test.dart `
  --reporter compact
```

Expected: FAIL because the registry and resolver are absent.

- [ ] **Step 3: Implement the generic registry**

```dart
final class VoiceProviderRegistry<T> {
  VoiceProviderRegistry(Iterable<MapEntry<VoiceEngine, T>> entries)
    : _providers = _build(entries);

  static Map<VoiceEngine, T> _build<T>(
    Iterable<MapEntry<VoiceEngine, T>> entries,
  ) {
    final providers = <VoiceEngine, T>{};
    for (final entry in entries) {
      if (providers.containsKey(entry.key)) {
        throw ArgumentError.value(entry.key, 'entries', 'duplicate engine');
      }
      providers[entry.key] = entry.value;
    }
    if (providers.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'must not be empty');
    }
    return Map<VoiceEngine, T>.unmodifiable(providers);
  }

  final Map<VoiceEngine, T> _providers;

  Set<VoiceEngine> get engines => Set<VoiceEngine>.unmodifiable(_providers.keys);

  T? providerFor(VoiceEngine engine) => _providers[engine];
}
```

- [ ] **Step 4: Implement the policy contract**

Use this exact context:

```dart
final class VoiceRouteContext {
  const VoiceRouteContext({
    required this.isOnline,
    required this.remoteStandardEnabled,
    required this.offlinePackAvailable,
    required this.voiceMirrorEnabled,
    required this.hasVoiceMirrorConsent,
    required this.hasActiveVoiceMirrorSession,
  });

  final bool isOnline;
  final bool remoteStandardEnabled;
  final bool offlinePackAvailable;
  final bool voiceMirrorEnabled;
  final bool hasVoiceMirrorConsent;
  final bool hasActiveVoiceMirrorSession;
}

abstract interface class VoicePolicySource {
  Future<VoiceRouteContext> load();
}

final class StaticVoicePolicySource implements VoicePolicySource {
  const StaticVoicePolicySource(this.context);

  final VoiceRouteContext context;

  @override
  Future<VoiceRouteContext> load() async => context;
}

final class VoiceRoutePlan {
  VoiceRoutePlan(Iterable<VoiceEngine> engines)
    : engines = List<VoiceEngine>.unmodifiable(engines) {
    if (this.engines.isEmpty) {
      throw ArgumentError.value(engines, 'engines', 'must not be empty');
    }
  }

  final List<VoiceEngine> engines;
}
```

`VoicePolicyResolver.resolve` returns only registered engines and applies:

```text
researchEvaluation -> assigned engine only, no fallback
offline standard -> offlinePack, nativeTts
online standard -> offlinePack, voxCpmStandard, omniVoice, nativeTts
online dynamic -> voxCpmStandard, omniVoice, nativeTts
session mirror -> voxCpmMirror, voxCpmStandard, omniVoice, nativeTts
```

The resolver throws `consentMissing` without mirror consent, `sessionExpired`
without an active mirror session, and `providerDisabled` when no permitted
engine is registered.

- [ ] **Step 5: Run policy tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```powershell
git add -- `
  lib/voice/voice_provider_registry.dart `
  lib/voice/voice_policy.dart `
  test/voice/voice_provider_registry_test.dart `
  test/voice/voice_policy_test.dart
git commit -m "feat(voice): add policy routing and provider registry"
```

### Task 3: Generalize synthesized audio providers and cache identity

**Files:**

- Create: `lib/voice/voice_synthesis_provider.dart`
- Create: `lib/voice/bundled_voice_asset_provider.dart`
- Modify: `lib/voice/omni_voice_provider.dart`
- Modify: `lib/voice/voice_audio_cache.dart`
- Remove: `lib/voice/omni_voice_asset_provider.dart`
- Test: `test/voice/omni_voice_provider_test.dart`
- Test: `test/voice/bundled_voice_asset_provider_test.dart`
- Test: `test/voice/voice_audio_cache_test.dart`
- Remove: `test/voice/omni_voice_asset_provider_test.dart`

**Interfaces:**

- Produces:
  - `VoiceAudio`
  - `VoiceSynthesisProvider`
  - `BundledVoiceAssetProvider`
  - provider-aware `VoiceAudioCacheKey`

- [ ] **Step 1: Write failing generic-provider tests**

```dart
test('cache key separates engines that synthesize identical text', () {
  final omni = VoiceAudioCacheKey.create(
    request: request,
    engine: VoiceEngine.omniVoice,
    modelVersion: 'omni-1',
  );
  final vox = VoiceAudioCacheKey.create(
    request: request,
    engine: VoiceEngine.voxCpmStandard,
    modelVersion: 'vox-1',
  );
  expect(omni, isNot(vox));
});

test('participant transient audio cannot enter standard cache', () {
  expect(
    () => VoiceAudioCacheKey.create(
      request: mirrorRequest,
      engine: VoiceEngine.voxCpmMirror,
      modelVersion: 'vox-1',
    ),
    throwsA(isA<VoiceFailure>()),
  );
});
```

- [ ] **Step 2: Run focused provider/cache tests and confirm failure**

```powershell
flutter test `
  test/voice/omni_voice_provider_test.dart `
  test/voice/bundled_voice_asset_provider_test.dart `
  test/voice/voice_audio_cache_test.dart `
  --reporter compact
```

Expected: FAIL because generic audio/provider types do not exist.

- [ ] **Step 3: Add the generic synthesis port**

```dart
import 'dart:typed_data';

import 'voice_models.dart';
import 'voice_provider_descriptor.dart';

final class VoiceAudio {
  VoiceAudio({
    required Uint8List bytes,
    required this.requestId,
    required this.engine,
    required this.modelVersion,
    required this.sampleRate,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final String requestId;
  final VoiceEngine engine;
  final String modelVersion;
  final int sampleRate;

  Uint8List get bytes => Uint8List.fromList(_bytes);
}

abstract interface class VoiceSynthesisProvider {
  VoiceProviderDescriptor get descriptor;

  Future<VoiceAudio> synthesize(VoiceRequest request);
}
```

- [ ] **Step 4: Migrate OmniVoice and bundled assets**

Make `OmniVoiceProvider` implement `VoiceSynthesisProvider`, declare engine
`omniVoice`, and map a successful response into `VoiceAudio`.

Replace `OmniVoiceAssetProvider` with `BundledVoiceAssetProvider`. Its
descriptor uses engine `offlinePack`, capability `standardTargetSpeech`,
privacy scope `standardContent`, and standard caching enabled. Keep the
existing sanitized asset-path behavior during P8-A.

Change `VoiceAudioCacheKey.create` to require `VoiceEngine engine`, include it
in equality/hash, and throw a validation failure unless the request privacy
scope is `standardContent`.

- [ ] **Step 5: Run provider/cache tests**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```powershell
git add -- `
  lib/voice/voice_synthesis_provider.dart `
  lib/voice/bundled_voice_asset_provider.dart `
  lib/voice/omni_voice_provider.dart `
  lib/voice/voice_audio_cache.dart `
  lib/voice/omni_voice_asset_provider.dart `
  test/voice/omni_voice_provider_test.dart `
  test/voice/bundled_voice_asset_provider_test.dart `
  test/voice/voice_audio_cache_test.dart `
  test/voice/omni_voice_asset_provider_test.dart
git commit -m "refactor(voice): generalize synthesized audio providers"
```

### Task 4: Replace HybridVoiceService with VoiceOrchestrator

**Files:**

- Create: `lib/voice/voice_route_handler.dart`
- Create: `lib/voice/native_voice_route_handler.dart`
- Create: `lib/voice/synthesized_voice_route_handler.dart`
- Create: `lib/voice/voice_orchestrator.dart`
- Remove: `lib/voice/hybrid_voice_service.dart`
- Modify: `lib/voice/voice_telemetry.dart`
- Test: `test/voice/voice_orchestrator_test.dart`
- Test: `test/voice/voice_orchestrator_cancellation_test.dart`
- Test: `test/voice/voice_orchestrator_telemetry_test.dart`
- Remove: `test/voice/hybrid_voice_service_test.dart`
- Remove: `test/voice/hybrid_voice_cancellation_test.dart`
- Remove: `test/voice/hybrid_voice_telemetry_test.dart`

**Interfaces:**

- Consumes:
  - `VoicePolicySource`
  - `VoicePolicyResolver`
  - `VoiceProviderRegistry<VoiceRouteHandler>`
- Produces:
  - `VoiceCancellationToken`
  - `VoiceRouteHandler`
  - `NativeVoiceRouteHandler`
  - `SynthesizedVoiceRouteHandler`
  - `VoiceOrchestrator implements VoiceProvider`

- [ ] **Step 1: Port current behavioral tests to orchestrator names**

Require:

- online practice tries remote then Native TTS once;
- offline pack precedes Native TTS;
- strict research never falls back;
- mirror is rejected without consent/session;
- a superseding request cancels the first request;
- `stop` cancels playback and all registered handlers;
- exactly one privacy-safe telemetry event is emitted;
- transient mirror audio is never cached.

Use a blocking fake handler to prove cancellation:

```dart
final first = orchestrator.speak(request);
await remote.started.future;
final second = orchestrator.speak(nextRequest);
await expectLater(first, throwsA(cancelledVoiceFailureMatcher));
remote.complete(nextAudio);
await expectLater(second, completes);
```

- [ ] **Step 2: Run orchestrator tests and confirm failure**

```powershell
flutter test `
  test/voice/voice_orchestrator_test.dart `
  test/voice/voice_orchestrator_cancellation_test.dart `
  test/voice/voice_orchestrator_telemetry_test.dart `
  --reporter compact
```

Expected: FAIL because the orchestrator and handlers do not exist.

- [ ] **Step 3: Implement cancellation and route handlers**

Define:

```dart
abstract interface class VoiceCancellationToken {
  bool get isCancelled;
  void throwIfCancelled();
}

abstract interface class VoiceRouteHandler {
  VoiceProviderDescriptor get descriptor;

  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  );

  Future<void> stop();
}
```

`NativeVoiceRouteHandler` delegates to the existing `NativeTtsProvider`.

`SynthesizedVoiceRouteHandler`:

1. validates that its descriptor supports the request capability;
2. reads/writes `VoiceAudioCache` only when both request and provider use
   standard content;
3. calls the generic `VoiceSynthesisProvider`;
4. checks cancellation after every await;
5. plays through `VoiceAudioPlayer`;
6. returns engine/model/request provenance;
7. never converts a provider failure into fallback itself.

- [ ] **Step 4: Implement VoiceOrchestrator**

The orchestrator:

1. increments a generation token;
2. stops existing audio;
3. loads one `VoiceRouteContext`;
4. resolves one ordered route plan;
5. tries each handler in order;
6. never falls back for validation, consent, session-expired, unsupported, or
   cancellation failures;
7. falls back only for `authentication`, `network`, `timeout`, `rateLimited`,
   `modelUnavailable`, `checksumMismatch`, `synthesis`, `playback`,
   `configuration`, and `unknown`;
8. emits one telemetry event;
9. exposes `stop` that invalidates the generation and stops all handlers.

Update telemetry schema to `voice_telemetry_v2` and add only:

```dart
'capability': capability.name,
'privacyScope': privacyScope.name,
```

Keep spoken text and voice ID absent.

- [ ] **Step 5: Run orchestrator and telemetry regressions**

```powershell
flutter test `
  test/voice/voice_orchestrator_test.dart `
  test/voice/voice_orchestrator_cancellation_test.dart `
  test/voice/voice_orchestrator_telemetry_test.dart `
  test/voice/voice_telemetry_test.dart `
  test/voice/firestore_voice_telemetry_test.dart `
  --reporter compact
```

Expected: PASS.

- [ ] **Step 6: Remove the old hybrid runtime spine and commit**

Run:

```powershell
rg -n "HybridVoiceService|hybrid_voice_service" lib test
```

Expected: no matches.

Commit:

```powershell
git add -- lib/voice test/voice
git commit -m "feat(voice): route providers through one orchestrator"
```

### Task 5: Centralize voice ownership in AppDependencies

**Files:**

- Modify: `lib/voice/voice_service_factory.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Create: `lib/runtime/scoped_voice_provider.dart`
- Modify:
  - `lib/screens/ai_tutor_screen.dart`
  - `lib/screens/cefr_article_reader_screen.dart`
  - `lib/screens/dictation_quiz_screen.dart`
  - `lib/screens/object_scanner_screen.dart`
  - `lib/screens/phonetic_explorer_screen.dart`
  - `lib/screens/shadowing_challenge_screen.dart`
  - `lib/screens/smart_audio_playlist_screen.dart`
  - `lib/screens/speak_to_text_screen.dart`
  - `lib/screens/sentence_scramble_screen.dart`
  - `lib/screens/srs_flashcards_screen.dart`
- Test: `test/voice/voice_service_factory_test.dart`
- Test: `test/runtime/app_bootstrap_test.dart`
- Test: `test/architecture/participant_screen_boundary_test.dart`
- Test: affected screen tests already under `test/screens/`

**Interfaces:**

- Consumes: `VoiceOrchestrator`
- Produces:
  - one lifecycle-managed `AppDependencies.voice`
  - `resolveScopedVoiceProvider(BuildContext, VoiceProvider?)`

- [ ] **Step 1: Write failing lifecycle and boundary tests**

Add an injected factory to the bootstrap test and prove exact-once disposal:

```dart
test('bootstrap owns and disposes one shared voice service', () async {
  final voice = RecordingManagedVoiceService();
  final dependencies = await bootstrap(
    voiceFactory: ({AppConfig? config}) => voice,
  ).initialize();
  expect(dependencies.voice, same(voice));
  await dependencies.dispose();
  await dependencies.dispose();
  expect(voice.disposeCalls, 1);
});
```

Extend the presentation boundary test to reject:

```dart
const forbidden = <String>[
  'VoiceServiceFactory',
  'ManagedVoiceService',
];
```

- [ ] **Step 2: Run lifecycle and architecture tests and confirm failure**

```powershell
flutter test `
  test/runtime/app_bootstrap_test.dart `
  test/architecture/participant_screen_boundary_test.dart `
  --reporter compact
```

Expected: FAIL because voice is still created and owned by individual screens.

- [ ] **Step 3: Build the production orchestrator in VoiceServiceFactory**

The factory registers:

- Native TTS handler;
- bundled offline handler;
- OmniVoice handler only when voice API configuration exists.

Use `StaticVoicePolicySource` with:

```dart
VoiceRouteContext(
  isOnline: true,
  remoteStandardEnabled: resolvedConfig != null,
  offlinePackAvailable: false,
  voiceMirrorEnabled: false,
  hasVoiceMirrorConsent: false,
  hasActiveVoiceMirrorSession: false,
)
```

P8-B replaces the static online/pack values with runtime sources. P8-A must
preserve current OmniVoice-to-Native fallback behavior.

- [ ] **Step 4: Add shared application ownership**

Add to `AppDependencies`:

```dart
final VoiceProvider voice;
```

Add this injectable builder to `AppBootstrap`:

```dart
typedef VoiceServiceBuilder = ManagedVoiceService Function({
  AppConfig? config,
});

ManagedVoiceService _createVoiceService({AppConfig? config}) {
  return VoiceServiceFactory.create(config: config);
}
```

The constructor accepts `VoiceServiceBuilder? voiceFactory` and stores
`voiceFactory ?? _createVoiceService`. Create one service during
initialization, and dispose it before the Gemini client, camera, speech, model,
and database resources.

Create:

```dart
VoiceProvider resolveScopedVoiceProvider(
  BuildContext context,
  VoiceProvider? override,
) {
  return override ?? AppDependenciesScope.of(context).voice;
}
```

- [ ] **Step 5: Remove screen-owned factories**

In each listed screen:

1. keep the optional `VoiceProvider` constructor parameter for tests;
2. resolve it in `didChangeDependencies` through
   `resolveScopedVoiceProvider`;
3. remove `VoiceServiceFactory` imports;
4. remove `_ownsVoiceProvider` and `ManagedVoiceService` type checks;
5. call `unawaited(_voice.stop())` during disposal where playback can remain
   active;
6. never dispose the shared service from a screen.

- [ ] **Step 6: Run focused runtime and screen tests**

```powershell
flutter test `
  test/voice `
  test/runtime/app_bootstrap_test.dart `
  test/architecture/participant_screen_boundary_test.dart `
  test/screens/ai_tutor_screen_test.dart `
  test/screens/cefr_article_reader_screen_test.dart `
  test/screens/dictation_quiz_screen_test.dart `
  test/screens/object_scanner_screen_test.dart `
  test/screens/phonetic_explorer_screen_test.dart `
  test/screens/shadowing_challenge_screen_test.dart `
  test/screens/smart_audio_playlist_screen_test.dart `
  test/screens/speak_to_text_screen_voice_test.dart `
  test/screens/sentence_scramble_screen_test.dart `
  test/screens/srs_flashcards_screen_test.dart `
  --reporter compact
```

Expected: PASS.

- [ ] **Step 7: Confirm the boundary and commit**

```powershell
rg -n "VoiceServiceFactory|ManagedVoiceService" lib/screens
```

Expected: no matches.

Commit:

```powershell
git add -- `
  lib/voice/voice_service_factory.dart `
  lib/runtime `
  lib/screens `
  test/voice/voice_service_factory_test.dart `
  test/runtime/app_bootstrap_test.dart `
  test/architecture/participant_screen_boundary_test.dart `
  test/screens
git commit -m "refactor(voice): centralize application voice lifecycle"
```

### Task 6: Add and run the bounded P8-A gate

**Files:**

- Create: `tool/cli/verify-voice-architecture.ps1`
- Create: `tool/cli/tests/verify-voice-architecture.tests.ps1`
- Create: `docs/development/p8a-voice-architecture-gate-2026-07-31.md`
- Modify:
  `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`

**Interfaces:**

- Produces one fail-closed P8-A verification command.

- [ ] **Step 1: Write the failing CLI contract test**

Require the gate to contain:

```powershell
$required = @(
  'flutter analyze',
  'flutter test',
  'flutter build apk --debug',
  'test/voice',
  'participant_screen_boundary_test.dart',
  'git diff --check'
)
```

Also assert that production screens contain neither `VoiceServiceFactory` nor
`ManagedVoiceService`, and that the old `hybrid_voice_service.dart` file is
absent.

- [ ] **Step 2: Run the CLI contract and confirm failure**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/tests/verify-voice-architecture.tests.ps1
```

Expected: FAIL because the gate script does not exist.

- [ ] **Step 3: Implement the bounded gate**

The gate runs exactly once:

```powershell
dart format --output=none --set-exit-if-changed lib/voice lib/runtime test/voice
flutter analyze
flutter test `
  test/voice `
  test/runtime/app_bootstrap_test.dart `
  test/architecture/participant_screen_boundary_test.dart `
  test/screens/ai_tutor_screen_test.dart `
  test/screens/cefr_article_reader_screen_test.dart `
  test/screens/dictation_quiz_screen_test.dart `
  test/screens/object_scanner_screen_test.dart `
  test/screens/phonetic_explorer_screen_test.dart `
  test/screens/shadowing_challenge_screen_test.dart `
  test/screens/smart_audio_playlist_screen_test.dart `
  test/screens/speak_to_text_screen_voice_test.dart `
  test/screens/sentence_scramble_screen_test.dart `
  test/screens/srs_flashcards_screen_test.dart `
  --reporter compact
flutter build apk --debug `
  --dart-define=LEXIQUEST_VERSION=1.0.0+p8a `
  --dart-define=LEXIQUEST_BUILD_ID=p8a-voice-architecture
git diff --check
```

It stops after the first failed phase and prints one phase summary. It does not
retry a failed command automatically.

- [ ] **Step 4: Run the P8-A gate**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-voice-architecture.ps1
```

Expected:

```text
LexiQuest P8-A voice architecture gate: PASS
```

- [ ] **Step 5: Record exact evidence**

Write the gate document with:

- source commit;
- Flutter/Dart versions;
- test counts;
- debug APK path, byte size, and SHA-256;
- analyzer result;
- screen-boundary result;
- a statement that VoxCPM runtime and voice mirroring remain P8-B/P8-C;
- no claim of new physical-device certification.

Mark P8-A complete in the master design only after the recorded gate passes.

- [ ] **Step 6: Commit Task 6**

```powershell
git add -- `
  tool/cli/verify-voice-architecture.ps1 `
  tool/cli/tests/verify-voice-architecture.tests.ps1 `
  docs/development/p8a-voice-architecture-gate-2026-07-31.md `
  docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md
git commit -m "test(voice): close P8-A architecture gate"
```

## P8-A Completion Check

P8-A is complete only when:

- `VoiceProvider` remains the only presentation-facing speech façade;
- provider selection is policy-driven and provider-neutral;
- existing OmniVoice and Native TTS behavior passes regression tests;
- participant-transient requests cannot enter the standard cache;
- application startup owns one voice service and disposes it once;
- participant screens no longer construct or dispose infrastructure services;
- the bounded CLI gate passes without retries;
- no P8-B/P8-C behavior is falsely reported as implemented.

After P8-A closes, write the separate P8-B implementation plan against the
actual interfaces committed by this package. Do not pre-implement VoxCPM,
download manifests, or temporary participant voice state inside P8-A.
