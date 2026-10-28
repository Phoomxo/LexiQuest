// Synthetic two-process persistence test. Host owns launch, force-stop and
// exact owned-directory cleanup. This target never opens the learner database.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../../integration_test/support/field_trial_external_fakes.dart';

const _suite = 'autonomous-persistence-two-phase-v1';
const _root =
    '/data/user/0/com.lexiquest.app/files/lexiquest-autonomous-persistence-20260908';
const _ownerPath =
    '/data/user/0/com.lexiquest.app/code_cache/lexiquest-autonomous-persistence-run-owned.json';
const _case = 'persistence phase commits or reopens canonical owned data';
const _sentinel = 'AUTONOMOUS_PERSISTENCE_FINAL_SENTINEL';
// Retained deliberately: phase A must die with the real connection open.
AppDependencies? _dependencies;
late String _canonicalRoot;
late String _canonicalCodeCache;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, dynamic>{
    'suite': _suite,
    'schemaVersion': 1,
    'passed': false,
    'sentinelCompleted': false,
    'syntheticData': true,
    'cloudEnabled': false,
    'researchEnabled': false,
    'gracefulDatabaseCloseBeforeDeath': false,
  };
  late Map<String, dynamic> owner;
  late String phase;

  void publish() {
    binding.reportData = {
      ...report,
      // This is a testWidgets integration fixture outside standard test dirs.
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
  }

  setUpAll(() async {
    expect(Platform.isAndroid, isTrue);
    // Android's Dart resolver can use /data/data while the shell uses
    // /data/user/0. Resolve the approved parent, then append the fixed child;
    // never resolve an arbitrary candidate and accept its own destination.
    final canonicalFiles = await Directory(
      '/data/user/0/com.lexiquest.app/files',
    ).resolveSymbolicLinks();
    _canonicalRoot =
        '$canonicalFiles/lexiquest-autonomous-persistence-20260908';
    _canonicalCodeCache = await Directory(
      '/data/user/0/com.lexiquest.app/code_cache',
    ).resolveSymbolicLinks();
    expect(
      await FileSystemEntity.type(_root, followLinks: false),
      FileSystemEntityType.directory,
    );
    expect(await Directory(_root).resolveSymbolicLinks(), _canonicalRoot);
    owner = await _readObject(File(_ownerPath));
    expect(owner['kind'], 'persistence');
    expect(owner['runId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(await _readObject(File('$_root/owner.json')), owner);
    phase = await File('$_root/phase-b.json').exists() ? 'b' : 'a';
    report.addAll({
      'runId': owner['runId'],
      'phase': phase,
      'pid': pid,
      'databasePath': '$_root/learning.sqlite',
    });
    final service = File(
      '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
    );
    expect(
      await Directory.systemTemp.resolveSymbolicLinks(),
      _canonicalCodeCache,
    );
    expect(
      await FileSystemEntity.type(service.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    final uri = (await developer.Service.getInfo()).serverUri;
    expect(uri, isNotNull);
    expect(uri!.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    await service.writeAsString(
      jsonEncode({'uri': uri.toString()}),
      flush: true,
    );
    print('PERSISTENCE_PHASE_START $phase');
    publish();
  });

  testWidgets(_case, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Synthetic persistence check')),
        ),
      ),
    );
    try {
      await tester.runAsync(() async {
        final dbFile = File('$_root/learning.sqlite');
        final witness = File('$_root/phase-a-witness.json');
        Map<String, dynamic>? before;
        if (phase == 'a') {
          expect(
            await FileSystemEntity.type(dbFile.path, followLinks: false),
            FileSystemEntityType.notFound,
            reason: 'Never reuse a prior fixture database',
          );
          expect(
            await FileSystemEntity.type(witness.path, followLinks: false),
            FileSystemEntityType.notFound,
          );
          expect(
            await FileSystemEntity.type('$_root/support', followLinks: false),
            FileSystemEntityType.notFound,
          );
          await Directory('$_root/support').create();
        } else {
          final request = await _readObject(File('$_root/phase-b.json'));
          expect(request['runId'], owner['runId']);
          expect(request['phase'], 'b');
          expect(request['databasePath'], dbFile.path);
          await _requireOwnedFile(dbFile);
          await _requireOwnedFile(witness);
          final bytes = await witness.readAsBytes();
          expect(
            sha256.convert(bytes).toString(),
            request['phaseAWitnessSha256'],
          );
          before = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          expect(before['runId'], owner['runId']);
          expect(before['databasePath'], dbFile.path);
          expect(before['pid'], request['expectedOldPid']);
          expect(
            before['pid'],
            isNot(pid),
            reason: 'A different native process must reopen the database',
          );
          report['previousPid'] = before['pid'];
        }
        expect(
          await FileSystemEntity.type('$_root/support', followLinks: false),
          FileSystemEntityType.directory,
        );
        expect(
          await Directory('$_root/support').resolveSymbolicLinks(),
          '$_canonicalRoot/support',
        );
        _dependencies = await AppBootstrap(
          initializeFirebase: () async =>
              throw StateError('Synthetic persistence cloud disabled'),
          initializeSupabase: () async =>
              throw StateError('Synthetic persistence cloud disabled'),
          loadConfig: () =>
              throw StateError('Synthetic persistence remote config disabled'),
          guestSessionService: _GuestSession(),
          createDatabase: () => AppDatabase(NativeDatabase(dbFile)),
          createEntryStateStore: () async => _GuestEntry(),
          applicationSupportDirectoryProvider: () async =>
              Directory('$_root/support'),
          learningTimezoneId: () => 'Asia/Bangkok',
          exportStoreFactory: HostFakeExportStore.new,
          cameraGatewayFactory: HostFakeCameraGateway.new,
          speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
          cloudSyncEnabled: false,
          buildAiTutor: (_) =>
              throw StateError('Synthetic persistence AI disabled'),
          buildVoice: (_) => _SilentVoice(),
        ).initialize();
        final dependencies = _dependencies!;
        if (phase == 'a') {
          final category = await dependencies.vocabulary!.createCategory(
            'Persistence synthetic words',
          );
          final word = await dependencies.vocabulary!.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'station',
              meaning: 'สถานี',
              partOfSpeech: 'noun',
            ),
          );
          final session = await dependencies.learning!.startQuiz(
            categoryId: category.id,
            limit: 1,
          );
          expect(session.questions, hasLength(1));
          expect(session.questions.single.word.id, word.id);
          final evidence = dependencies.currentActivityEvidence!.capture(
            ownerId: session.ownerId,
            input: CurrentActivityInput.typedRecall,
            sessionId: session.id,
            wordId: word.id,
            isCorrect: true,
            responseTimeMs: 1200,
            attemptNumber: 1,
          );
          await evidence.record();
          await dependencies.learning!.finishSession(session.id);
        }
        await dependencies.learningReconciliation!.drain();
        final canonical = await _canonical(dependencies);
        if (phase == 'a') {
          // Flush the witness only after committed API writes and projections.
          // Keep the DB open; no disposal/checkpoint is substituted for death.
          await witness.create(exclusive: true);
          await witness.writeAsString(
            jsonEncode({
              'runId': owner['runId'],
              'pid': pid,
              'databasePath': dbFile.path,
              'canonical': canonical,
            }),
            flush: true,
          );
        } else {
          expect(
            canonical,
            before!['canonical'],
            reason:
                'Canonical committed rows and projections must survive actual process death exactly',
          );
          report['canonicalReadbackMatched'] = true;
        }
        report['canonical'] = canonical;
        report['witnessSha256'] = sha256
            .convert(await witness.readAsBytes())
            .toString();
        report['connectionRetainedForHostStop'] = true;
      });
      expect(tester.takeException(), isNull);
      report['passed'] = true;
      print('PERSISTENCE_PHASE_PASS $phase');
    } catch (error) {
      report['errorType'] = error.runtimeType.toString();
      rethrow;
    } finally {
      publish();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(_sentinel, (tester) async {
    expect(report['passed'], isTrue);
    expect(_dependencies, isNotNull);
    report['sentinelCompleted'] = true;
    print('PERSISTENCE_PHASE_COMPLETE $phase');
    publish();
  });
  tearDownAll(publish);
}

Future<Map<String, dynamic>> _readObject(File file) async {
  await _requireOwnedFile(file);
  expect(await file.length(), lessThan(100000));
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

Future<void> _requireOwnedFile(File file) async {
  final expected = switch (file.path) {
    _ownerPath =>
      '$_canonicalCodeCache/lexiquest-autonomous-persistence-run-owned.json',
    '$_root/owner.json' => '$_canonicalRoot/owner.json',
    '$_root/phase-b.json' => '$_canonicalRoot/phase-b.json',
    '$_root/phase-a-witness.json' => '$_canonicalRoot/phase-a-witness.json',
    '$_root/learning.sqlite' => '$_canonicalRoot/learning.sqlite',
    _ => throw StateError('Unreviewed persistence file path'),
  };
  expect(
    await FileSystemEntity.type(file.path, followLinks: false),
    FileSystemEntityType.file,
  );
  expect(await file.resolveSymbolicLinks(), expected);
}

Future<Map<String, Object?>> _canonical(AppDependencies d) async {
  final owner = await d.localOwners!.getOrCreateActiveOwner();
  final categories = await d.vocabulary!.watchCategories().first;
  expect(categories, hasLength(1));
  final category = categories.single;
  expect(category.name, 'Persistence synthetic words');
  final words = await d.vocabulary!.watchWords(category.id).first;
  expect(words, hasLength(1));
  final word = words.single;
  expect(word.spelling, 'station');
  expect(word.meaning, 'สถานี');
  final db = d.database!;
  final attempts = await db.select(db.answerAttempts).get();
  final sessions = await db.select(db.learningSessions).get();
  final srs = await db.select(db.srsStates).get();
  expect(attempts, hasLength(1));
  expect(sessions, hasLength(1));
  expect(srs, hasLength(1));
  expect(attempts.single.ownerId, owner.id);
  expect(attempts.single.wordId, word.id);
  expect(attempts.single.isCorrect, isTrue);
  expect(sessions.single.endedAtUtcMs, isNotNull);
  expect(srs.single.lastReviewAtUtcMs, isNotNull);
  expect(await db.select(db.researchConsents).get(), isEmpty);
  expect(await db.select(db.experimentAssignments).get(), isEmpty);
  expect(await db.select(db.assessmentRuns).get(), isEmpty);
  final progress = await d.progress!.load();
  expect(progress.sampleSize, 1);
  expect(progress.completedSessions, 1);
  final reward = await d.rewards!.load();
  return {
    'ownerId': owner.id,
    'category': {
      'id': category.id,
      'ownerId': category.ownerId,
      'name': category.name,
    },
    'word': {
      'id': word.id,
      'categoryId': word.categoryId,
      'spelling': word.spelling,
      'meaning': word.meaning,
      'partOfSpeech': word.partOfSpeech,
    },
    'attempts': [attempts.single.toJson()],
    'sessions': [sessions.single.toJson()],
    'srs': [srs.single.toJson()],
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
    'researchRows': 0,
  };
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
