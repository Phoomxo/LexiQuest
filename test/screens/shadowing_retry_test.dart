import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  for (final loseAnswerAck in [true, false]) {
    testWidgets(
      'retrying shadowing after ${loseAnswerAck ? 'lost answer acknowledgement' : 'failed finish'} records one answer',
      (tester) async {
        final database = db.AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'synthetic-shadowing-owner',
          nowUtc: () => DateTime.utc(2026, 10, 28),
        );
        final owner = await owners.getOrCreateActiveOwner();
        await database
            .into(database.vocabularyCategories)
            .insert(
              db.VocabularyCategoriesCompanion.insert(
                id: 'synthetic-category',
                ownerId: owner.id,
                name: 'Audit',
                normalizedName: 'audit',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await database
            .into(database.vocabularyWords)
            .insert(
              db.VocabularyWordsCompanion.insert(
                id: 'synthetic-word',
                ownerId: owner.id,
                categoryId: 'synthetic-category',
                spelling: 'station',
                normalizedSpelling: 'station',
                meaning: 'synthetic meaning',
                normalizedMeaning: 'synthetic meaning',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        final repository = _LostAcknowledgementRepository(
          DriftLearningRepository(database),
          loseAnswerAck: loseAnswerAck,
        );
        var sequence = 0;
        final learning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'synthetic-${++sequence}',
          nowUtc: () => DateTime.utc(2026, 10, 28),
          buildInfo: const AppBuildInfo(version: 'audit', buildId: '6500cbf3'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ShadowingChallengeScreen(
              learning: learning,
              voice: VoiceUseCases(_SilentVoice()),
              speechPractice: SpeechPracticeUseCases(_SyntheticSpeech()),
            ),
          ),
        );
        await _until(tester, () => find.text('station').evaluate().isNotEmpty);
        final button = find.byKey(const ValueKey('shadowing-listen-button'));
        await tester.tap(button);
        await _until(
          tester,
          () => find
              .text('วิเคราะห์เสียงได้แต่บันทึกประวัติไม่สำเร็จ')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('บันทึกอีกครั้ง'), findsOneWidget);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        await tester.pumpAndSettle();

        await tester.tap(button);
        await _until(tester, () => repository.successfulFinishes == 1);
        final attempts = await database.select(database.answerAttempts).get();
        final session = await database
            .select(database.learningSessions)
            .getSingle();
        expect(session.activityType, 'shadowing');
        expect(session.acceptedPlanId, isNull);
        expect(session.checkpointRevision, 0);
        final points = await database
            .select(database.pointsLedgerEntries)
            .get();
        expect(
          {
            'answers': attempts.length,
            'xp': points.fold<int>(0, (sum, entry) => sum + entry.amount),
          },
          {'answers': 1, 'xp': 1},
          reason:
              'The first correct answer committed before its acknowledgement was lost.',
        );
        expect(repository.recordCalls, loseAnswerAck ? 2 : 1);
      },
    );
  }
}

final class _LostAcknowledgementRepository implements LearningRepository {
  _LostAcknowledgementRepository(this.delegate, {required this.loseAnswerAck});
  final DriftLearningRepository delegate;
  final bool loseAnswerAck;
  bool lostFirstAcknowledgement = false;
  int successfulFinishes = 0;
  int recordCalls = 0;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    limit: limit,
  );
  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    recordCalls++;
    final result = await delegate.recordAnswer(command);
    if (loseAnswerAck && !lostFirstAcknowledgement) {
      lostFirstAcknowledgement = true;
      throw StateError('synthetic post-commit lost acknowledgement');
    }
    return result;
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    if (!loseAnswerAck && !lostFirstAcknowledgement) {
      lostFirstAcknowledgement = true;
      throw StateError('synthetic failed session finish');
    }
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    successfulFinishes++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SyntheticSpeech implements SpeechRecognitionGateway {
  @override
  bool isListening = false;
  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;
  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}
  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'station',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 10, 28),
        engine: 'synthetic-stt',
        locale: locale,
      ),
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

final class _SilentVoice implements VoiceProvider {
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
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Synthetic shadowing flow did not complete after bounded pumps.');
}
