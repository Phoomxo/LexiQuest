import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/achievements/application/achievement_share_card_use_cases.dart';
import 'package:vocab_learning_app/features/achievements/data/file_selector_share_card_store.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('share-card artifacts have no public construction path', () {
    final source = File(
      'lib/features/achievements/application/achievement_share_card_use_cases.dart',
    ).readAsStringSync();

    expect(source, contains('final class AchievementShareCardArtifact'));
    expect(source, contains('AchievementShareCardArtifact._('));
    expect(source, isNot(contains('AchievementShareCardArtifact({')));
  });

  test(
    'creates a byte-for-byte deterministic safe SVG only for a current canonical unlock',
    () async {
      final store = _RecordingShareCardStore();
      final useCases = AchievementShareCardUseCases(store: store);

      final first = await useCases.share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );
      final second = await useCases.share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );

      expect(first.status, AchievementShareCardStatus.saved);
      expect(second.status, AchievementShareCardStatus.saved);
      expect(
        first.artifact.suggestedFileName,
        'lexiquest-first_session-v7.svg',
      );
      expect(first.artifact.mimeType, 'image/svg+xml');
      expect(first.artifact.bytes, orderedEquals(second.artifact.bytes));
      final text = utf8.decode(first.artifact.bytes);
      expect(text, contains('เรียนจบเซสชันแรก'));
      expect(text, contains('Definition v7'));
      expect(text, isNot(contains('owner-1')));
      expect(text, isNot(contains('firebase-user-1')));
      expect(text, isNot(contains('session-evidence-1')));
      expect(text, isNot(contains('answer-attempt-1')));
      expect(text, isNot(contains('event-1')));
      expect(store.selectionCalls, 2);
      expect(store.writeCalls, 2);
    },
  );

  test(
    'rejects locked unknown mismatched and unsafe unlock metadata before destination selection',
    () async {
      final store = _RecordingShareCardStore();
      final useCases = AchievementShareCardUseCases(store: store);

      for (final request
          in <({ProgressSnapshot progress, String id, int version})>[
            (progress: _emptyProgress(), id: 'first_session', version: 7),
            (
              progress: _progress(),
              id: 'not-a-canonical-achievement',
              version: 7,
            ),
            (progress: _progress(), id: 'first_session', version: 6),
            (
              progress: _progress(
                sourceEventId: '../owner-1\\private\\answer-attempt-1',
              ),
              id: 'first_session',
              version: 7,
            ),
            (
              progress: _progress(sourceEventId: 'event\u0000control'),
              id: 'first_session',
              version: 7,
            ),
          ]) {
        await expectLater(
          useCases.share(
            progress: request.progress,
            achievementId: request.id,
            definitionVersion: request.version,
            confirmed: true,
          ),
          throwsA(isA<AchievementShareCardException>()),
        );
      }

      expect(store.selectionCalls, 0);
      expect(store.writeCalls, 0);
    },
  );

  test(
    'requires explicit confirmation before destination selection or write',
    () async {
      final store = _RecordingShareCardStore();
      final useCases = AchievementShareCardUseCases(store: store);

      await expectLater(
        useCases.share(
          progress: _progress(),
          achievementId: 'first_session',
          definitionVersion: 7,
          confirmed: false,
        ),
        throwsA(
          isA<AchievementShareCardException>().having(
            (error) => error.code,
            'code',
            AchievementShareCardFailureCode.confirmationRequired,
          ),
        ),
      );

      expect(store.selectionCalls, 0);
      expect(store.writeCalls, 0);
    },
  );

  test(
    'user cancellation returns cancelled without writing an artifact',
    () async {
      final store = _RecordingShareCardStore()
        ..nextResult = const AchievementShareCardStoreResult.cancelled();
      final useCases = AchievementShareCardUseCases(store: store);

      final result = await useCases.share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );

      expect(result.status, AchievementShareCardStatus.cancelled);
      expect(store.selectionCalls, 1);
      expect(store.writeCalls, 0);
      expect(store.savedArtifacts, isEmpty);
    },
  );

  test(
    'an in-flight repeated confirmed operation selects and writes once',
    () async {
      final store = _RecordingShareCardStore()..blockNextSelection();
      final useCases = AchievementShareCardUseCases(store: store);
      final first = useCases.share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );
      await store.selectionStarted.future;
      final repeated = useCases.share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );

      store.releaseSelection();
      final results = await Future.wait([first, repeated]);

      expect(
        results.map((result) => result.status),
        everyElement(AchievementShareCardStatus.saved),
      );
      expect(store.selectionCalls, 1);
      expect(store.writeCalls, 1);
      expect(store.savedArtifacts, hasLength(1));
    },
  );

  test(
    'Android picker cancellation is typed after one exact native request',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.lexiquest.app/export');
      var invocations = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        invocations += 1;
        expect(call.method, 'saveExportFile');
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(
          arguments.keys,
          unorderedEquals(<String>['suggestedName', 'mimeType', 'bytes']),
        );
        expect(arguments['suggestedName'], 'lexiquest-first_session-v7.svg');
        expect(arguments['mimeType'], 'image/svg+xml');
        expect(arguments['bytes'], isA<Uint8List>());
        expect(
          arguments['bytes'],
          orderedEquals((await _canonicalArtifact()).bytes),
        );
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final result = await FileSelectorShareCardStore(
        isAndroid: true,
      ).selectDestinationAndSave(await _canonicalArtifact());

      expect(result.status, AchievementShareCardStoreStatus.cancelled);
      expect(result.destination, isNull);
      expect(invocations, 1);
    },
  );
}

Future<AchievementShareCardArtifact> _canonicalArtifact() async {
  final result =
      await AchievementShareCardUseCases(
        store: _RecordingShareCardStore(),
      ).share(
        progress: _progress(),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );
  return result.artifact;
}

ProgressSnapshot _progress({String sourceEventId = 'session-evidence-1'}) =>
    ProgressSnapshot(
      sampleSize: 2,
      correctCount: 2,
      wrongCount: 0,
      accuracy: 1,
      totalXp: 2,
      completedSessions: 1,
      streakDays: 1,
      dueReviewCount: 0,
      masteredWordCount: 0,
      achievementCount: 1,
      gameLevel: 1,
      skills: const [],
      weaknesses: const [],
      recommendations: const [],
      achievements: [
        AchievementEvidence(
          id: 'first_session',
          definitionVersion: 7,
          sourceEventId: sourceEventId,
          unlockedAtUtc: DateTime.utc(2026, 8, 30),
        ),
      ],
    );

ProgressSnapshot _emptyProgress() => const ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final class _RecordingShareCardStore implements AchievementShareCardStore {
  final savedArtifacts = <AchievementShareCardArtifact>[];
  final selectionStarted = Completer<void>();
  Completer<void>? _selectionRelease;
  AchievementShareCardStoreResult nextResult =
      const AchievementShareCardStoreResult.saved(
        destination: 'content://downloads/lexiquest.svg',
      );
  var selectionCalls = 0;
  var writeCalls = 0;

  void blockNextSelection() => _selectionRelease = Completer<void>();

  void releaseSelection() {
    final release = _selectionRelease;
    if (release == null || release.isCompleted) {
      throw StateError('no share-card selection is blocked');
    }
    release.complete();
  }

  @override
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  ) async {
    selectionCalls += 1;
    if (!selectionStarted.isCompleted) selectionStarted.complete();
    final release = _selectionRelease;
    if (release != null) await release.future;
    if (nextResult.status == AchievementShareCardStoreStatus.saved) {
      writeCalls += 1;
      savedArtifacts.add(artifact);
    }
    return nextResult;
  }
}
