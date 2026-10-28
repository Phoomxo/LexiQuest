import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'device-camera-benchmark.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/review/application/pair_review_deferral.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import '../../integration_test/support/field_trial_external_fakes.dart';
import '../../integration_test/support/persistent_manual_qa_storage.dart';
import '../../test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness;
import '../../test/features/learning/pair_matching/pair_matching_source_composer_test.dart'
    as fixture;

const words = manualQaWords;

void _manualStage(String stage) {
  debugPrint('MANUAL_UAT_STAGE $stage pid=$pid');
}

Future<void> main() async {
  _manualStage('main-enter');
  WidgetsFlutterBinding.ensureInitialized();
  _manualStage(
    'binding-ready type=${WidgetsBinding.instance.runtimeType} '
    'lifecycle=${WidgetsBinding.instance.lifecycleState}',
  );
  _manualStage('storage-start');
  final directory = await openPersistentManualQaDirectory(
    await getApplicationSupportDirectory(),
  );
  _manualStage('storage-ready');
  final voice = _LocalVoice();
  _manualStage('bootstrap-start');
  final dependencies = await AppBootstrap(
    initializeFirebase: () async =>
        throw StateError('Local QA: cloud disabled'),
    initializeSupabase: () async =>
        throw StateError('Local QA: cloud disabled'),
    loadConfig: () => throw StateError('Local QA: remote services disabled'),
    guestSessionService: _GuestSession(),
    createDatabase: () =>
        AppDatabase(NativeDatabase(File('${directory.path}/learning.sqlite'))),
    createEntryStateStore: () async => _GuestEntry(),
    applicationSupportDirectoryProvider: () async =>
        Directory('${directory.path}/support')..createSync(recursive: true),
    exportStoreFactory: HostFakeExportStore.new,
    cloudSyncEnabled: false,
    buildAiTutor: (_) => throw StateError('Local QA: AI unavailable'),
    buildVoice: (_) => voice,
  ).initialize();
  _manualStage('bootstrap-end');
  _manualStage('seeding-start');
  await seedManualQaVocabulary(
    dependencies.database!,
    dependencies.vocabulary!,
  );
  _manualStage('seeding-end');
  _manualStage('run-app-start');
  runApp(
    MaterialApp(
      theme: M3Theme.lightTheme,
      home: _Launcher(dependencies: dependencies, voice: voice),
    ),
  );
  _manualStage('run-app-returned');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _manualStage(
      'first-post-frame lifecycle=${WidgetsBinding.instance.lifecycleState}',
    );
  });
  debugPrint(
    'MANUAL_UAT_READY native-camera native-speech local-tts research-off',
  );
}

class _Launcher extends StatefulWidget {
  const _Launcher({required this.dependencies, required this.voice});
  final AppDependencies dependencies;
  final _LocalVoice voice;
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  final fixtures = <PairHarness>[];
  bool busy = false;
  String status = '';
  Future<void> benchmarkCamera(bool candidate, ModelDelegate delegate) async {
    if (busy) return;
    setState(() {
      busy = true;
      status =
          'กำลังวัด ${candidate ? 'candidate' : 'baseline'} ${delegate.name}';
    });
    try {
      final support = await getApplicationSupportDirectory();
      final staged = Directory('${support.path}/camera-benchmark');
      final result = await saveStagedCameraBenchmark(
        stagedDirectory: staged,
        candidate: candidate,
        delegate: delegate,
      );
      debugPrint('CAMERA_BENCHMARK_SAVED ${result.path}');
      if (mounted) {
        setState(() => status = 'บันทึก benchmark แล้ว: ${result.path}');
      }
    } catch (error) {
      debugPrint('CAMERA_BENCHMARK_FAILED $error');
      if (mounted) setState(() => status = 'Benchmark ไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.dependencies.dispose().ignore();
    super.dispose();
  }

  Future<void> openPair(PairDensity density, PairDirection direction) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final items = [
        for (var i = 0; i < density.pairCount; i++)
          fixture.fixture(i, spelling: words[i].$1, meaning: words[i].$2),
      ];
      final plan =
          (fixture.compose(
                    items,
                    launch: fixture.intent(
                      density: density,
                      direction: direction,
                    ),
                  )
                  as PairPlanReady)
              .plan;
      final h = PairHarness(
        pinnedPlan: plan,
        density: density,
        direction: direction,
      );
      fixtures.add(h);
      await h.initialize();
      final learning = LearningUseCases(
        owners: h.learning.owners,
        repository: h.real,
        generateId: h.learning.generateId,
        nowUtc: () => DateTime.now().toUtc(),
        buildInfo: h.learning.buildInfo,
      );
      final allowlist = PairCuratedAllowlist(
        version: plan.allowlistVersion,
        items: plan.orderedLexicalItems,
      );
      final clock = Stopwatch()..start();
      final runtime = PairMatchingExperienceRuntime(
        database: h.db,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        registry: buildLessonModeRegistry(
          internalPairMatching: true,
          matchingDeliveryState: LessonModeDeliveryState.enabled,
        ),
        createController: (adapter) => UnifiedLessonController(
          learning: learning,
          adapter: adapter,
          sessionPurposeReader: h.real,
        ),
        composer: PairMatchingSourceComposer(allowlist: allowlist),
        reviewDeferral: PairReviewDeferral(h.db),
        voice: widget.dependencies.voice,
        features: const BuildFeatureRegistry.fieldDefaults(),
        start: PairMatchingAtomicStartAdapter(
          repository: h.real,
          capability: InternalPairMatchingCapability(
            allowlist: allowlist,
            isEnabled: () => true,
          ),
        ),
        canStart: () => true,
        monotonicMicros: () => clock.elapsedMicroseconds,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => PairMatchingExperienceHost.recover(
            runtime: runtime,
            operation: h.operation,
            onExit: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => status = 'เปิดรอบไม่ได้: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> play(String language) async {
    _manualStage('tts-$language-request');
    setState(() => status = 'กำลังเล่นเสียง');
    try {
      final result = await widget.voice.speak(
        VoiceRequest.create(
          text: language == 'en'
              ? 'Hello. This is a LexiQuest voice test.'
              : 'สวัสดี นี่คือการทดสอบเสียง',
          language: language,
          voiceId: 'manual-qa',
          speed: 1,
          contentId: 'manual-qa',
          contentType: 'test',
          mode: VoiceMode.practice,
          localOnly: true,
        ),
      );
      _manualStage(
        'tts-$language-start-returned '
        'hasCompletion=${result.playbackCompleted != null}',
      );
      await result.playbackCompleted?.timeout(const Duration(seconds: 40));
      _manualStage('tts-$language-completion-await-returned');
      if (mounted) setState(() => status = 'เล่นเสียงจบแล้ว');
    } catch (error) {
      _manualStage('tts-$language-error type=${error.runtimeType}');
      if (mounted) setState(() => status = 'เสียงไม่พร้อม: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LexiQuest — ทดสอบบนเครื่อง')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'ใช้คำตัวอย่างและฐานข้อมูลทดสอบแยก กล้องและไมโครโฟนเป็นของเครื่องจริง',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.all(16),
            minimumSize: const Size(48, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.school_outlined),
          onPressed: () {
            _manualStage('open-app-button');
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) {
                  _manualStage('open-app-route-builder');
                  return MyApp(
                    dependencies: widget.dependencies,
                    ownsDependencies: false,
                  );
                },
              ),
            );
          },
          label: const Text('เปิดแอปเพื่อทดสอบการใช้งาน'),
        ),
        const SizedBox(height: 24),
        Text('ทดสอบเสียงอ่าน', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        OutlinedButton(
          style: _menuButtonStyle,
          onPressed: () => play('en'),
          child: const Text('ฟังเสียงภาษาอังกฤษ'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: _menuButtonStyle,
          onPressed: () => play('th'),
          child: const Text('ฟังเสียงภาษาไทย'),
        ),
        const SizedBox(height: 24),
        Text(
          'ทดสอบจับคู่คำศัพท์',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('เลือกจำนวนคู่และทิศทางที่ต้องการฝึก'),
        const SizedBox(height: 12),
        for (final density in PairDensity.values)
          for (final direction in PairDirection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                style: _menuButtonStyle,
                onPressed: busy ? null : () => openPair(density, direction),
                child: Text(
                  'จับคู่ ${density.pairCount} คู่ — ${direction == PairDirection.enToTh ? 'อังกฤษ → ไทย' : 'ไทย → อังกฤษ'}',
                ),
              ),
            ),
        const SizedBox(height: 24),
        Text(
          'Camera benchmark · local QA',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'ภาพ book เดียว · เปิดแอปใหม่ก่อนแต่ละเงื่อนไข · RSS แบบสุ่มวัด',
        ),
        for (final candidate in [false, true])
          for (final delegate in [ModelDelegate.cpu, ModelDelegate.xnnpack])
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                style: _menuButtonStyle,
                onPressed: busy
                    ? null
                    : () => benchmarkCamera(candidate, delegate),
                child: Text(
                  'Benchmark ${candidate ? 'candidate' : 'baseline'} ${delegate.name}',
                ),
              ),
            ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(status)),
          ),
      ],
    ),
  );
}

final _menuButtonStyle = OutlinedButton.styleFrom(
  alignment: Alignment.centerLeft,
  minimumSize: const Size(48, 56),
  padding: const EdgeInsets.all(16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

class _GuestEntry implements AppEntryStateStore {
  @override
  Future<void> clear() async {}
  @override
  Future<void> markGuest() async {}
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

class _LocalVoice implements ManagedVoiceProvider {
  final native = NativeTtsProvider(FlutterTtsAdapter());
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest r) => native.speak(
    VoiceRequest.create(
      text: r.text,
      language: r.language,
      voiceId: r.voiceId,
      speed: r.speed,
      contentId: r.contentId,
      contentType: r.contentType,
      mode: r.mode,
      localOnly: true,
    ),
  );
  @override
  Future<void> stop() => native.stop();
  @override
  Future<void> dispose() => native.stop();
}
