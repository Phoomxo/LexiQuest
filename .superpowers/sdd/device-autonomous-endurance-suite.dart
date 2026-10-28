// Synthetic, phase-aware Android endurance workload. The host owns the
// private directory, native lifecycle, process death, evidence and restore.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/packaged_starter_identity.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../../integration_test/support/field_trial_external_fakes.dart';

const _suite = 'autonomous-endurance-real-clock-v1';
const _ownerPath =
    '/data/user/0/com.lexiquest.app/code_cache/'
    'lexiquest-autonomous-endurance-run-owned.json';
const _base =
    '/data/user/0/com.lexiquest.app/files/'
    'lexiquest-autonomous-endurance-20260908';
const _case = 'endurance phase completes measured learning workload';
const _sentinel = 'AUTONOMOUS_ENDURANCE_PHASE_SENTINEL';
const _modes = <String>[
  'quiz',
  'cloze',
  'definition',
  'scramble',
  'srs',
  'associative',
];

late IntegrationTestWidgetsFlutterBinding _binding;
AppDependencies? _retainedDependencies;

void main() {
  HttpOverrides.global = _NoNetwork();
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{
    'schemaVersion': 1,
    'suite': _suite,
    'passed': false,
    'cancelled': false,
    'sentinelCompleted': false,
    'syntheticData': true,
    'cloudEnabled': false,
    'researchEnabled': false,
    'screenshotsRequested': false,
  };

  void publish() {
    _binding.reportData = <String, dynamic>{
      ...report,
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': _binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
  }

  testWidgets(_case, (tester) async {
    _Fixture? fixture;
    try {
      expect(Platform.isAndroid, isTrue);
      final owner = await tester.runAsync(() => _readObject(File(_ownerPath)));
      expect(owner, isNotNull);
      final runId = owner!['runId'];
      expect(runId, isA<String>());
      expect(runId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(owner['kind'], 'endurance');
      final root = Directory('$_base/$runId');
      await tester.runAsync(
        () => _requireOwnedDirectory(root, runId as String),
      );
      final plan = await tester.runAsync(() => _PhasePlan.load(root, runId));
      expect(plan, isNotNull);
      report.addAll({
        'runId': runId,
        'profile': plan!.profile,
        'phase': plan.phase,
        'phaseDurationSeconds': plan.phaseDurationSeconds,
        'hostElapsedAtLaunchMs': plan.hostElapsedAtLaunchMs,
        'pid': pid,
        'startedUtc': DateTime.now().toUtc().toIso8601String(),
      });
      await tester.runAsync(_publishService);
      fixture = await tester.runAsync(() => _Fixture.create(root, plan));
      expect(fixture, isNotNull);
      _retainedDependencies = fixture!.dependencies;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MyApp(dependencies: fixture.dependencies, ownsDependencies: false),
      );
      await _wait(tester, _page('ChooseModeScreen'));
      final workload = _Workload(tester, fixture, plan);
      final outcome = await workload.run();
      report.addAll(outcome);
      report['connectionRetainedForHostStop'] = true;
      report['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
      report['passed'] = outcome['phasePassed'] == true;
      report['cancelled'] = outcome['cancelled'] == true;
      publish();
    } catch (error) {
      report['errorType'] = error.runtimeType.toString();
      report['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
      publish();
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 64)));

  testWidgets(_sentinel, (tester) async {
    expect(_retainedDependencies, isNotNull);
    report['sentinelCompleted'] = true;
    publish();
    print('AUTONOMOUS_ENDURANCE_PHASE_COMPLETE ${report['phase']}');
  });
  tearDownAll(publish);
}

Future<void> _publishService() async {
  final service = File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  );
  expect(
    await FileSystemEntity.type(service.path, followLinks: false),
    FileSystemEntityType.notFound,
  );
  final uri = (await developer.Service.getInfo()).serverUri;
  expect(uri, isNotNull);
  expect(uri!.scheme, 'http');
  expect(uri.host, '127.0.0.1');
  await service.writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}

final class _PhasePlan {
  const _PhasePlan({
    required this.runId,
    required this.profile,
    required this.phase,
    required this.phaseDurationSeconds,
    required this.hostElapsedAtLaunchMs,
    required this.expectedPreviousCheckpointSha256,
  });

  final String runId;
  final String profile;
  final int phase;
  final int phaseDurationSeconds;
  final int hostElapsedAtLaunchMs;
  final String? expectedPreviousCheckpointSha256;

  int get roundDurationSeconds => profile == 'full' ? 1800 : 60;
  int get requiredTotalSeconds => profile == 'full' ? 10800 : 360;

  static Future<_PhasePlan> load(Directory root, String runId) async {
    File? selected;
    for (var phase = 2; phase >= 0; phase--) {
      final candidate = File('${root.path}/phase-$phase.json');
      if (await candidate.exists()) {
        selected = candidate;
        break;
      }
    }
    if (selected == null) throw StateError('Endurance phase request missing');
    final value = await _readObject(selected);
    final profile = value['profile'];
    final phase = value['phase'];
    final seconds = value['phaseDurationSeconds'];
    final expectedSeconds = profile == 'full' ? 3600 : 120;
    if (value.length != 9 ||
        value['schemaVersion'] != 1 ||
        value['runId'] != runId ||
        (profile != 'full' && profile != 'smoke') ||
        phase is! int ||
        phase < 0 ||
        phase > 2 ||
        selected.path != '${root.path}/phase-$phase.json' ||
        seconds != expectedSeconds ||
        value['phaseCount'] != 3 ||
        value['seed'] != 20260908 ||
        value['hostElapsedAtLaunchMs'] is! int ||
        value['hostElapsedAtLaunchMs'] < 0 ||
        (value['expectedPreviousCheckpointSha256'] != null &&
            !_shaPattern.hasMatch(
              value['expectedPreviousCheckpointSha256'] as String,
            ))) {
      throw StateError('Invalid bounded endurance phase request');
    }
    return _PhasePlan(
      runId: runId,
      profile: profile as String,
      phase: phase,
      phaseDurationSeconds: seconds as int,
      hostElapsedAtLaunchMs: value['hostElapsedAtLaunchMs'] as int,
      expectedPreviousCheckpointSha256:
          value['expectedPreviousCheckpointSha256'] as String?,
    );
  }
}

final class _Fixture {
  const _Fixture(this.root, this.plan, this.dependencies, this.starterWords);

  final Directory root;
  final _PhasePlan plan;
  final AppDependencies dependencies;
  final List<VocabularyWord> starterWords;

  static Future<_Fixture> create(Directory root, _PhasePlan plan) async {
    final database = AppDatabase(
      NativeDatabase(File('${root.path}/learning.sqlite')),
    );
    AppDependencies? dependencies;
    try {
      dependencies = await AppBootstrap(
        initializeFirebase: () async =>
            throw StateError('Endurance cloud disabled'),
        initializeSupabase: () async =>
            throw StateError('Endurance cloud disabled'),
        loadConfig: () => throw StateError('Endurance remote config disabled'),
        guestSessionService: _GuestSession(),
        createDatabase: () => database,
        createEntryStateStore: () async => _GuestEntry(),
        applicationSupportDirectoryProvider: () async {
          final directory = Directory('${root.path}/support');
          if (!await directory.exists()) await directory.create();
          return directory;
        },
        learningTimezoneId: () => 'Asia/Bangkok',
        exportStoreFactory: HostFakeExportStore.new,
        cameraGatewayFactory: HostFakeCameraGateway.new,
        speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
        cloudSyncEnabled: false,
        buildAiTutor: (_) => throw StateError('Endurance AI disabled'),
        buildVoice: (_) => _SilentVoice(),
      ).initialize();
      expect(database.schemaVersion, 26);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        26,
        reason: 'Each owned endurance database must use the current schema',
      );
      expect(dependencies.runtimeStatus.starterContentFailure, isNull);
      final words = await dependencies.vocabulary!.getGameWords(limit: 100);
      expect(words, hasLength(12));
      expect(words.every((word) => word.isReadOnly), isTrue);
      expect(
        words.every(
          (word) => word.categoryId == PackagedStarterIdentity.categoryId,
        ),
        isTrue,
      );
      final pinned = await dependencies.vocabulary!.readPinnedByIds(
        words.map((word) => word.id),
      );
      expect(pinned.every((word) => word.richMetadata != null), isTrue);
      if (plan.phase == 0 &&
          !(await File('${root.path}/seeded.json').exists())) {
        await _seedSixDueReviews(dependencies, plan.runId, root);
      }
      return _Fixture(root, plan, dependencies, List.unmodifiable(pinned));
    } catch (_) {
      await dependencies?.dispose();
      if (dependencies == null) await database.close();
      rethrow;
    }
  }
}

final class _Workload {
  _Workload(this.tester, this.fixture, this.plan);

  final WidgetTester tester;
  final _Fixture fixture;
  final _PhasePlan plan;
  final Stopwatch stopwatch = Stopwatch();
  late _CheckpointChain chain;
  var uiActionCount = 0;
  var completedSessions = 0;
  var cancelled = false;
  var fillerIndex = 0;
  var lastActionMs = 0;
  var maxActionGapMs = 0;
  var lastCheckpointMs = 0;
  late int beforePhaseWorkloadMs;
  Map<String, int> modeCompleted = {for (final mode in _modes) mode: 0};

  Future<Map<String, Object?>> run() async {
    chain = await _CheckpointChain.load(fixture.root);
    beforePhaseWorkloadMs = chain.latest?.cumulativeWorkloadMs ?? 0;
    final previous = chain.latest;
    if (plan.phase == 0) {
      expect(previous, isNull);
      expect(plan.expectedPreviousCheckpointSha256, isNull);
    } else {
      expect(previous, isNotNull);
      expect(previous!.phase, plan.phase - 1);
      expect(previous.sha256, plan.expectedPreviousCheckpointSha256);
      completedSessions = previous.completedSessions;
      uiActionCount = previous.uiActionCount;
      modeCompleted = Map<String, int>.of(previous.modeCompleted);
      expect(
        await _canonical(),
        previous.canonical,
        reason: 'Exact canonical rows/projections must survive process death',
      );
    }
    stopwatch.start();
    await _writeCheckpoint('phase-start');
    while (stopwatch.elapsed < Duration(seconds: plan.phaseDurationSeconds)) {
      if (await _cancelRequested()) {
        cancelled = true;
        break;
      }
      final mode = _nextRequiredMode();
      final before = await _terminalSessionCount();
      await switch (mode) {
        'quiz' => _quiz(tester, fixture, _action),
        'cloze' => _cloze(tester, fixture, _action),
        'definition' => _definition(tester, fixture, _action),
        'scramble' => _scramble(tester, _action),
        'srs' => _srs(tester, _action),
        'associative' => _associative(tester, _action),
        _ => throw StateError('Unknown endurance mode'),
      };
      final after = await _terminalSessionCount();
      expect(
        after,
        before + 1,
        reason: '$mode must commit one terminal session',
      );
      completedSessions++;
      modeCompleted[mode] = modeCompleted[mode]! + 1;
      if (stopwatch.elapsedMilliseconds - lastCheckpointMs >= 30000) {
        await _writeCheckpoint('session-complete', mode: mode);
      }
      if (cancelled) break;
    }
    await fixture.dependencies.learningReconciliation!.drain();
    _observeActionGap();
    stopwatch.stop();
    final canonical = await _canonical();
    await _writeCheckpoint(cancelled ? 'cancelled' : 'phase-complete');
    final phasePassed =
        !cancelled &&
        stopwatch.elapsedMilliseconds >= plan.phaseDurationSeconds * 1000 &&
        _hasRequiredCoverage() &&
        maxActionGapMs <= 75000 &&
        canonical['researchRows'] == 0 &&
        canonical['duplicateAnswerIds'] == 0 &&
        canonical['duplicateRewardIds'] == 0 &&
        canonical['activeSessionCount'] == 0 &&
        canonical['foreignOwnerRows'] == 0 &&
        _NoNetwork.attempts == 0;
    return <String, Object?>{
      'phasePassed': phasePassed,
      'cancelled': cancelled,
      'phaseStopwatchMs': stopwatch.elapsedMilliseconds,
      'cumulativeWorkloadMs':
          (beforePhaseWorkloadMs + stopwatch.elapsedMilliseconds),
      'uiActionCount': uiActionCount,
      'completedSessionCount': completedSessions,
      'modeCompleted': modeCompleted,
      'canonical': canonical,
      'latestCheckpointSha256': chain.latest!.sha256,
      'checkpointCount': chain.count,
      'maxActionGapMs': maxActionGapMs,
      'canonicalReadbackMatched': plan.phase > 0,
      'starterWordIdsSha256': _wordIdsSha(fixture.starterWords),
      'setupSeedSessionCount': 1,
      'setupSeedAttemptCount': 6,
      'cloudCallCount': _NoNetwork.attempts,
    };
  }

  void _action() {
    _observeActionGap();
    uiActionCount++;
  }

  void _observeActionGap() {
    final now = stopwatch.elapsedMilliseconds;
    final gap = now - lastActionMs;
    if (gap > maxActionGapMs) maxActionGapMs = gap;
    expect(gap, lessThanOrEqualTo(75000), reason: 'No unproven action gap');
    lastActionMs = now;
  }

  String _nextRequiredMode() {
    // Due reviews are consumed through the real SRS screen before ordinary
    // practice reschedules these same starter words for future days. No clock
    // travel or direct SRS mutation manufactures another due deck mid-run.
    if (modeCompleted['srs']! < (plan.profile == 'full' ? 6 : 1)) {
      return 'srs';
    }
    if (plan.profile == 'smoke') {
      if (plan.phase == 0) {
        return _modes.firstWhere(
          (mode) => modeCompleted[mode] == 0,
          orElse: _nextFiller,
        );
      }
      return plan.phase == 1 ? 'quiz' : 'definition';
    }
    final globalMs = beforePhaseWorkloadMs + stopwatch.elapsedMilliseconds;
    final round = (globalMs ~/ Duration(minutes: 30).inMilliseconds).clamp(
      0,
      5,
    );
    final target = round + 1;
    return _modes.firstWhere(
      (mode) => modeCompleted[mode]! < target,
      orElse: _nextFiller,
    );
  }

  String _nextFiller() {
    const fillers = <String>[
      'quiz',
      'cloze',
      'definition',
      'scramble',
      'associative',
    ];
    final result = fillers[fillerIndex % fillers.length];
    fillerIndex++;
    return result;
  }

  bool _hasRequiredCoverage() {
    if (plan.profile == 'smoke') {
      return plan.phase == 0
          ? _modes.every((mode) => modeCompleted[mode]! >= 1)
          : true;
    }
    final required = (plan.phase + 1) * 2;
    return _modes.every((mode) => modeCompleted[mode]! >= required);
  }

  Future<bool> _cancelRequested() async {
    final file = File('${fixture.root.path}/cancel.json');
    if (!await file.exists()) return false;
    final value = await _readObject(file);
    return value.length == 2 &&
        value['schemaVersion'] == 1 &&
        value['runId'] == plan.runId;
  }

  Future<int> _terminalSessionCount() async {
    final rows = await fixture.dependencies.database!
        .select(fixture.dependencies.database!.learningSessions)
        .get();
    return rows.where((row) => row.state == 'completed').length;
  }

  Future<void> _writeCheckpoint(String event, {String? mode}) async {
    final canonical = await _canonical();
    final elapsedMs = stopwatch.elapsedMilliseconds;
    await chain.append(<String, Object?>{
      'schemaVersion': 1,
      'runId': plan.runId,
      'profile': plan.profile,
      'phase': plan.phase,
      'event': event,
      'mode': mode,
      'pid': pid,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'phaseStopwatchMs': elapsedMs,
      'cumulativeWorkloadMs': beforePhaseWorkloadMs + elapsedMs,
      'hostElapsedMs': plan.hostElapsedAtLaunchMs + elapsedMs,
      'uiActionCount': uiActionCount,
      'maxActionGapMs': maxActionGapMs,
      'completedSessionCount': completedSessions,
      'modeCompleted': modeCompleted,
      'canonical': canonical,
      'cancelState': cancelled ? 'acknowledged' : 'none',
    });
    lastCheckpointMs = stopwatch.elapsedMilliseconds;
  }

  Future<Map<String, Object?>> _canonical() async {
    await fixture.dependencies.learningReconciliation!.drain();
    final database = fixture.dependencies.database!;
    final attempts = await database.select(database.answerAttempts).get();
    final sessions = await database.select(database.learningSessions).get();
    final srs = await database.select(database.srsStates).get();
    final rewards = await database.select(database.rewardTransactions).get();
    var researchRows = 0;
    researchRows +=
        (await database.select(database.researchConsents).get()).length;
    researchRows +=
        (await database.select(database.experimentAssignments).get()).length;
    researchRows +=
        (await database.select(database.assessmentRuns).get()).length;
    researchRows +=
        (await database.select(database.motivationMeasurementRuns).get())
            .length;
    researchRows +=
        (await database.select(database.motivationResponses).get()).length;
    researchRows +=
        (await database.select(database.researchParticipationPermits).get())
            .length;
    researchRows +=
        (await database.select(database.measurementOpportunities).get()).length;
    researchRows +=
        (await database.select(database.researchSessionProofs).get()).length;
    final attemptIds = attempts.map((row) => row.id).toSet();
    final rewardIds = rewards.map((row) => row.id).toSet();
    final srsWords = srs.map((row) => row.wordId).toSet();
    final owner = await fixture.dependencies.localOwners!
        .getOrCreateActiveOwner();
    final progress = await fixture.dependencies.progress!.load();
    final reward = await fixture.dependencies.rewards!.load();
    String digestRows(Iterable<Map<String, dynamic>> rows) {
      final encoded = rows.map(jsonEncode).toList()..sort();
      return sha256.convert(utf8.encode(encoded.join('\n'))).toString();
    }

    return <String, Object?>{
      'ownerId': owner.id,
      'starterCategoryId': PackagedStarterIdentity.categoryId,
      'starterWordIdsSha256': _wordIdsSha(fixture.starterWords),
      'sessionCount': sessions.length,
      'terminalSessionCount': sessions
          .where((row) => row.state == 'completed')
          .length,
      'activeSessionCount': sessions
          .where((row) => row.state == 'active')
          .length,
      'foreignOwnerRows':
          attempts.where((row) => row.ownerId != owner.id).length +
          sessions.where((row) => row.ownerId != owner.id).length +
          srs.where((row) => row.ownerId != owner.id).length +
          rewards.where((row) => row.ownerId != owner.id).length,
      'answerAttemptCount': attempts.length,
      'uniqueAnswerAttemptCount': attemptIds.length,
      'duplicateAnswerIds': attempts.length - attemptIds.length,
      'srsWordCount': srsWords.length,
      'rewardTransactionCount': rewards.length,
      'uniqueRewardTransactionCount': rewardIds.length,
      'duplicateRewardIds': rewards.length - rewardIds.length,
      'uniqueRewardSourceCount': rewards
          .map((row) => row.sourceEventId)
          .whereType<String>()
          .toSet()
          .length,
      'researchRows': researchRows,
      'attemptRowsSha256': digestRows(attempts.map((row) => row.toJson())),
      'sessionRowsSha256': digestRows(sessions.map((row) => row.toJson())),
      'srsRowsSha256': digestRows(srs.map((row) => row.toJson())),
      'rewardRowsSha256': digestRows(rewards.map((row) => row.toJson())),
      'progress': {
        'sampleSize': progress.sampleSize,
        'correctCount': progress.correctCount,
        'wrongCount': progress.wrongCount,
        'completedSessions': progress.completedSessions,
        'totalXp': progress.totalXp,
      },
      'rewards': {
        'balance': reward.balance,
        'transactionCount': reward.transactionCount,
      },
    };
  }
}

final class _CheckpointChain {
  _CheckpointChain(this.root, this.rows);

  final Directory root;
  final List<_Checkpoint> rows;

  _Checkpoint? get latest => rows.isEmpty ? null : rows.last;
  int get count => rows.length;

  static Future<_CheckpointChain> load(Directory root) async {
    final files = await root
        .list(followLinks: false)
        .where(
          (entry) => RegExp(r'checkpoint-\d{4}\.json$').hasMatch(entry.path),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    if (files.length > 512) throw StateError('Checkpoint bound exceeded');
    final rows = <_Checkpoint>[];
    String? previous;
    for (var index = 0; index < files.length; index++) {
      final expectedName =
          'checkpoint-${index.toString().padLeft(4, '0')}.json';
      if (files[index].uri.pathSegments.last != expectedName) {
        throw StateError('Checkpoint sequence is not contiguous');
      }
      final bytes = await files[index].readAsBytes();
      if (bytes.length > 200000) throw StateError('Checkpoint too large');
      final sha = sha256.convert(bytes).toString();
      final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (value['sequence'] != index || value['previousSha256'] != previous) {
        throw StateError('Checkpoint hash chain mismatch');
      }
      rows.add(_Checkpoint.from(value, sha));
      previous = sha;
    }
    return _CheckpointChain(root, rows);
  }

  Future<void> append(Map<String, Object?> value) async {
    if (rows.length >= 512) throw StateError('Checkpoint bound exceeded');
    final sequence = rows.length;
    final payload = <String, Object?>{
      ...value,
      'sequence': sequence,
      'previousSha256': latest?.sha256,
    };
    final raw = utf8.encode(jsonEncode(payload));
    final file = File(
      '${root.path}/checkpoint-${sequence.toString().padLeft(4, '0')}.json',
    );
    await file.create(exclusive: true);
    await file.writeAsBytes(raw, flush: true);
    final sha = sha256.convert(raw).toString();
    rows.add(_Checkpoint.from(Map<String, dynamic>.from(payload), sha));
  }
}

final class _Checkpoint {
  const _Checkpoint({
    required this.sha256,
    required this.phase,
    required this.cumulativeWorkloadMs,
    required this.completedSessions,
    required this.uiActionCount,
    required this.modeCompleted,
    required this.canonical,
  });

  final String sha256;
  final int phase;
  final int cumulativeWorkloadMs;
  final int completedSessions;
  final int uiActionCount;
  final Map<String, int> modeCompleted;
  final Map<String, dynamic> canonical;

  factory _Checkpoint.from(Map<String, dynamic> value, String sha) {
    final encodedModes = value['modeCompleted'];
    if (value['schemaVersion'] != 1 ||
        value['phase'] is! int ||
        value['cumulativeWorkloadMs'] is! int ||
        value['completedSessionCount'] is! int ||
        value['uiActionCount'] is! int ||
        encodedModes is! Map ||
        encodedModes.keys.toSet().difference(_modes.toSet()).isNotEmpty ||
        _modes.any((mode) => encodedModes[mode] is! int)) {
      throw StateError('Malformed endurance checkpoint');
    }
    return _Checkpoint(
      sha256: sha,
      phase: value['phase'] as int,
      cumulativeWorkloadMs: value['cumulativeWorkloadMs'] as int,
      completedSessions: value['completedSessionCount'] as int,
      uiActionCount: value['uiActionCount'] as int,
      modeCompleted: {
        for (final mode in _modes) mode: encodedModes[mode] as int,
      },
      canonical: Map<String, dynamic>.from(value['canonical'] as Map),
    );
  }
}

Future<void> _quiz(
  WidgetTester tester,
  _Fixture fixture,
  void Function() action,
) async {
  await _mode(tester, 'home/learn/quiz', 'QuizScreen', action);
  final words = await fixture.dependencies.vocabulary!.getGameWords(limit: 100);
  final meanings = words
      .where((word) => find.text(word.spelling).evaluate().isNotEmpty)
      .map((word) => word.meaning)
      .toSet();
  expect(meanings, hasLength(1));
  await _tap(tester, find.text(meanings.single), action: action);
  await _tap(tester, _key('meaning-quiz-next'), action: action);
  await _finishScore(tester, action);
}

Future<void> _cloze(
  WidgetTester tester,
  _Fixture fixture,
  void Function() action,
) async {
  await _mode(tester, 'home/learn/quiz/cloze', 'FillInTheBlanksScreen', action);
  await _wait(tester, _key('cloze-prompt'));
  final prompt = tester.widget<Text>(_key('cloze-prompt')).data!;
  final correct = fixture.starterWords.singleWhere(
    (word) => word.richMetadata!.examples.any(
      (example) => example.replaceFirst(word.spelling, '_____') == prompt,
    ),
  );
  await _tap(tester, _key('cloze-mode-typed'), action: action);
  await _wait(tester, _key('cloze-typed-answer'));
  await tester.enterText(_key('cloze-typed-answer'), correct.spelling);
  action();
  await _tap(tester, _key('cloze-submit-typed'), action: action);
  await _tap(tester, _key('cloze-next'), action: action);
  await _finishScore(tester, action);
}

Future<void> _definition(
  WidgetTester tester,
  _Fixture fixture,
  void Function() action,
) async {
  await _mode(
    tester,
    'home/learn/quiz/definition',
    'DefinitionQuizScreen',
    action,
  );
  await _wait(tester, _key('definition-quiz-prompt'));
  final prompt = tester.widget<Text>(_key('definition-quiz-prompt')).data!;
  final correct = fixture.starterWords.singleWhere(
    (word) => word.richMetadata!.englishDefinition == prompt,
  );
  await _tap(
    tester,
    _key('definition-quiz-option-${correct.id}-${correct.spelling}'),
    action: action,
  );
  await _tap(tester, _key('definition-quiz-next'), action: action);
  await _finishScore(tester, action);
}

Future<void> _scramble(WidgetTester tester, void Function() action) async {
  await _mode(
    tester,
    'home/learn/quiz/word-scramble',
    'WordScrambleScreen',
    action,
  );
  final target = tester
      .widget<WordScrambleScreen>(_page('WordScrambleScreen'))
      .word;
  final scrambled = createStableScramble(target);
  final used = <int>{};
  for (final character in target.characters) {
    final index = List<int>.generate(scrambled.length, (value) => value)
        .firstWhere(
          (value) => !used.contains(value) && scrambled[value] == character,
        );
    used.add(index);
    await _tap(tester, _key('word-letter-$index'), action: action);
  }
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'ตรวจสอบคำตอบ'),
    action: action,
  );
  await _wait(tester, _key('word-scramble-complete'));
  await tester.pageBack();
  action();
  await _wait(tester, _page('ChooseModeScreen'));
}

Future<void> _srs(WidgetTester tester, void Function() action) async {
  await _mode(tester, 'home/learn/srs', 'SrsFlashcardsScreen', action);
  await _tap(tester, _key('flashcard-reveal-answer'), action: action);
  await _wait(tester, _key('flashcard-not-remembered'));
  await _tap(tester, _key('flashcard-not-remembered'), action: action);
  await _wait(tester, _page('ChooseModeScreen'));
}

Future<void> _associative(WidgetTester tester, void Function() action) async {
  await _mode(
    tester,
    'home/learn/associative-reading',
    'AssociativeReadingLauncherScreen',
    action,
  );
  final start = find.widgetWithText(FilledButton, 'เริ่มอ่าน');
  await _wait(tester, start);
  final freshRound = find.text('เริ่มรอบใหม่');
  await _tap(
    tester,
    freshRound.evaluate().isNotEmpty ? freshRound : start,
    action: action,
  );
  final screen = tester.widget<AssociativeReadingSessionScreen>(
    _page('AssociativeReadingSessionScreen'),
  );
  for (var stage = 1; stage <= 2; stage++) {
    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
      action: action,
    );
  }
  final recallFields = find.descendant(
    of: _page('AssociativeReadingSessionScreen'),
    matching: find.byType(TextField),
  );
  expect(recallFields, findsNWidgets(screen.targetWords.length));
  for (var index = 0; index < screen.targetWords.length; index++) {
    await tester.enterText(recallFields.at(index), screen.targetWords[index]);
    action();
  }
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
    action: action,
  );
  final cueFields = find.descendant(
    of: _page('AssociativeReadingSessionScreen'),
    matching: find.byType(TextField),
  );
  expect(cueFields, findsNWidgets(screen.targetWords.length));
  for (var index = 0; index < screen.targetWords.length; index++) {
    await tester.enterText(
      cueFields.at(index),
      'cue ${screen.targetWords[index]}',
    );
    action();
  }
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
    action: action,
  );
  final contextField = find.descendant(
    of: _page('AssociativeReadingSessionScreen'),
    matching: find.byType(TextField),
  );
  expect(contextField, findsOneWidget);
  await tester.enterText(contextField, 'I use ${screen.targetWords.first}.');
  action();
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
    action: action,
  );
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'จบกิจกรรม'),
    action: action,
  );
  await _wait(tester, _page('AssociativeReadingLauncherScreen'));
  await _tap(
    tester,
    find.descendant(
      of: _page('AssociativeReadingLauncherScreen'),
      matching: find.byType(BackButton),
    ),
    action: action,
  );
  await _wait(tester, _page('ChooseModeScreen'));
}

Future<void> _finishScore(WidgetTester tester, void Function() action) async {
  await _wait(tester, _page('ScoreScreen'));
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'กลับไปเลือกกิจกรรม'),
    action: action,
  );
  await _wait(tester, _page('ChooseModeScreen'));
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));
Finder _page(String type) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == type,
  description: 'production page $type',
);

Future<void> _mode(
  WidgetTester tester,
  String key,
  String page,
  void Function() action,
) async {
  final homeScroll = find
      .descendant(
        of: _page('ChooseModeScreen'),
        matching: find.byType(Scrollable),
      )
      .first;
  await _wait(tester, homeScroll, requireHitTestable: true);
  // Each mode returns to the same lazy list at its previous scroll offset.
  // Reset through bounded gestures before locating the next mode below it.
  for (var index = 0; index < 12; index++) {
    if (tester.state<ScrollableState>(homeScroll).position.pixels <= 0) break;
    await tester.drag(homeScroll, const Offset(0, 600));
    action();
    await tester.pump(const Duration(milliseconds: 250));
    _checkNoException(tester);
  }
  expect(tester.state<ScrollableState>(homeScroll).position.pixels, 0);
  await tester.scrollUntilVisible(
    _key(key),
    220,
    scrollable: homeScroll,
    maxScrolls: 40,
    continuous: true,
  );
  action();
  await _tap(tester, _key(key), action: action);
  await _wait(tester, _key('session-configuration-sheet'));
  await _tap(tester, _key('session-options-toggle'), action: action);
  await tester.ensureVisible(_key('session-item-count'));
  await tester.enterText(_key('session-item-count'), '1');
  action();
  await _tap(tester, _key('session-config-start'), action: action);
  await _wait(tester, _page(page));
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  required void Function() action,
}) async {
  await _wait(tester, target);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
  // Let the native IME settle, then scroll again before the single real tap.
  for (
    var attempt = 0;
    attempt < 12 && target.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    _checkNoException(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 25));
  }
  await _wait(tester, target, requireHitTestable: true);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  action();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  _checkNoException(tester);
}

// Host regression seam: exercises the same readiness wait used on Android.
Future<void> waitForEnduranceTarget(
  WidgetTester tester,
  Finder target, {
  bool requireHitTestable = false,
}) => _wait(tester, target, requireHitTestable: requireHitTestable);

Future<void> _wait(
  WidgetTester tester,
  Finder target, {
  bool requireHitTestable = false,
}) async {
  for (var index = 0; index < 300; index++) {
    await tester.pump(const Duration(milliseconds: 25));
    final candidates = target.evaluate().toList(growable: false);
    // A returning page can already be current/hit-testable while the outgoing
    // page is still animating. Observe the mounted page routes as well.
    final pageTransitionActive = find.byType(Scaffold).evaluate().any((
      element,
    ) {
      final animation = ModalRoute.of(element)?.animation;
      return animation?.status == AnimationStatus.forward ||
          animation?.status == AnimationStatus.reverse;
    });
    if (!pageTransitionActive &&
        candidates.isNotEmpty &&
        candidates.every((element) {
          final route = ModalRoute.of(element);
          if (route == null) return true;
          return route.isCurrent &&
              (route.animation == null || route.animation!.isCompleted) &&
              (route.secondaryAnimation == null ||
                  route.secondaryAnimation!.isDismissed);
        }) &&
        (!requireHitTestable ||
            target.hitTestable().evaluate().length == candidates.length)) {
      return;
    }
    if (requireHitTestable && candidates.length == 1) {
      await tester.ensureVisible(target);
    }
    _checkNoException(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  final visibleText = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .take(40)
      .toList();
  final buttons = find
      .byType(FilledButton)
      .evaluate()
      .map((element) => (element.widget as FilledButton).onPressed != null)
      .toList();
  fail(
    'Bounded endurance wait failed: $target; synthetic UI=$visibleText; enabledButtons=$buttons',
  );
}

void _checkNoException(WidgetTester tester) {
  expect(tester.takeException(), isNull, reason: 'No swallowed Flutter error');
}

Future<void> _seedSixDueReviews(
  AppDependencies dependencies,
  String runId,
  Directory root,
) async {
  var clock = DateTime.now().toUtc().subtract(const Duration(days: 2));
  var sequence = 0;
  final repository = DriftLearningRepository(dependencies.database!);
  final learning = LearningUseCases(
    owners: dependencies.localOwners!,
    repository: repository,
    generateId: () => 'endurance-setup-$runId-${++sequence}',
    nowUtc: () => clock,
    buildInfo: const AppBuildInfo(
      version: 'synthetic',
      buildId: 'autonomous-endurance',
    ),
  );
  final session = await learning.startQuiz(
    categoryId: PackagedStarterIdentity.categoryId,
    limit: 6,
  );
  expect(session.questions, hasLength(6));
  for (var index = 0; index < session.questions.length; index++) {
    final word = session.questions[index].word;
    clock = clock.add(const Duration(seconds: 1));
    await learning.recordEvidence(
      sourceEvidenceId: 'attempt:endurance-setup-$runId-$index',
      occurredAtUtc: clock,
      sessionId: session.id,
      wordId: word.id,
      promptMode: 'srsRecall',
      isCorrect: false,
      responseTimeMs: 200,
      attemptNumber: index + 1,
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'srs-recall',
        hintLevel: 0,
        contentRevision: 'packaged-starter-r1',
        engagementAllowed: true,
      ),
    );
  }
  clock = clock.add(const Duration(seconds: 1));
  await learning.finishSession(session.id);
  final due = await repository.listDueWords(
    ownerId: session.ownerId!,
    nowUtc: DateTime.now().toUtc(),
    limit: 10,
  );
  expect(due, hasLength(6));
  final marker = File('${root.path}/seeded.json');
  await marker.create(exclusive: true);
  await marker.writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'runId': runId,
      'setupSessionCount': 1,
      'setupAttemptCount': 6,
      'dueWordIdsSha256': sha256
          .convert(
            utf8.encode(
              (due.map((word) => word.id).toList()..sort()).join('\n'),
            ),
          )
          .toString(),
    }),
    flush: true,
  );
}

Future<Map<String, dynamic>> _readObject(File file) async {
  expect(
    await FileSystemEntity.type(file.path, followLinks: false),
    FileSystemEntityType.file,
  );
  expect(await file.length(), lessThan(200000));
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic>) throw StateError('Expected JSON object');
  return value;
}

Future<void> _requireOwnedDirectory(Directory root, String runId) async {
  expect(
    await FileSystemEntity.type(root.path, followLinks: false),
    FileSystemEntityType.directory,
  );
  final canonicalFiles = await Directory(
    '/data/user/0/com.lexiquest.app/files',
  ).resolveSymbolicLinks();
  expect(
    await root.resolveSymbolicLinks(),
    '$canonicalFiles/lexiquest-autonomous-endurance-20260908/$runId',
  );
  final owner = await _readObject(File('${root.path}/owner.json'));
  expect(owner['runId'], runId);
  expect(owner['kind'], 'endurance');
}

String _wordIdsSha(List<VocabularyWord> words) => sha256
    .convert(
      utf8.encode((words.map((word) => word.id).toList()..sort()).join('\n')),
    )
    .toString();

final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

final class _NoNetwork extends HttpOverrides {
  static int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Ordinary bootstrap constructs dormant clients for optional downloads.
    // Count and reject an actual connection attempt before any socket opens.
    return super.createHttpClient(context)
      ..connectionFactory = (uri, proxyHost, proxyPort) {
        attempts++;
        throw StateError('Endurance fixture rejects external HTTP connections');
      };
  }
}

final class _GuestEntry implements AppEntryStateStore {
  @override
  Future<void> clear() async {}
  @override
  Future<void> markGuest() async {}
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

final class _SilentVoice implements ManagedVoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
