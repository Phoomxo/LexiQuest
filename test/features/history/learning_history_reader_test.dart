import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_calendar_reader.dart';
import 'package:vocab_learning_app/features/progress/data/drift_personal_learning_profile_reader.dart';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import '../../support/pair_purpose_fixture.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';

final class _ObservedHistoryTime implements LearningTimeRepository {
  _ObservedHistoryTime(this.delegate);
  final LearningTimeRepository delegate;
  final hydrated = <String>[];
  @override
  Future<void> append(LearningTimeSegment segment) => delegate.append(segment);
  @override
  Future<Duration> activeDuration(String sessionId) {
    hydrated.add(sessionId);
    return delegate.activeDuration(sessionId);
  }
}

void main() {
  late AppDatabase database;
  late DriftLearningHistoryReader reader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    reader = DriftLearningHistoryReader(
      database,
      learningTime: DriftLearningTimeRepository(
        database,
        owners: const _Owners('owner:history'),
      ),
      nowUtc: () => DateTime.utc(2026, 8, 31, 12),
    );
    await _seedOwnerAndWord(database);
    await _seedPack(database);
  });

  tearDown(() => database.close());

  test(
    'B02 history first answers agree with progress and calendar without rewriting summary',
    () async {
      final when = DateTime.utc(2026, 8, 31, 9);
      await _seedTerminalSession(
        database,
        id: 'first-six',
        state: 'completed',
        startedAtUtc: when,
        endedAtUtc: when.add(const Duration(minutes: 10)),
        configuration: _configuration(
          mode: LessonMode.typedRecall,
          itemCount: 6,
        ),
        correctCount: 6,
        wrongCount: 1,
        score: 86,
      );
      final template =
          (await database.select(database.vocabularyWords).get()).single;
      final context = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'retention',
        hintLevel: 0,
        contentRevision: 'old-1',
        engagementAllowed: false,
      );
      for (var i = 0; i < 6; i++) {
        await database
            .into(database.vocabularyWords)
            .insert(
              template.copyWith(
                id: 'first-word-$i',
                spelling: 'word$i',
                normalizedSpelling: 'word$i',
              ),
            );
        await _seedAttemptAndEvent(
          database,
          sessionId: 'first-six',
          attemptId: 'first-$i',
          wordId: 'first-word-$i',
          isCorrect: i < 5,
          attemptNumber: i + 1,
          occurredAtUtc: when.add(Duration(seconds: i)),
          evidence: context,
        );
      }
      await _seedAttemptAndEvent(
        database,
        sessionId: 'first-six',
        attemptId: 'repair',
        wordId: 'first-word-5',
        isCorrect: true,
        attemptNumber: 7,
        occurredAtUtc: when.add(const Duration(minutes: 1)),
        evidence: context,
      );
      final before = await _sourceSnapshot(database);
      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history'),
      )).single;
      expect(entry.firstAnswers, (correct: 5, total: 6));
      expect(entry.repairAnswers, (correct: 1, total: 1));
      expect(
        entry.correctCount,
        6,
      ); // Stored historical aggregate stays intact.
      expect(entry.score, 86);
      final progress = await DriftProgressQueries(
        database,
      ).load(ownerId: 'owner:history', nowUtc: when);
      timezone_data.initializeTimeZones();
      final calendar = await DriftLearningCalendarReader(database).loadWeek(
        ownerId: 'owner:history',
        referenceUtc: when,
        timezoneId: 'UTC',
      );
      expect(progress.correctCount, entry.firstAnswers.correct);
      expect(progress.sampleSize, entry.firstAnswers.total);
      expect(calendar.weekly.accuracy.correctCount, entry.firstAnswers.correct);
      expect(calendar.weekly.accuracy.sampleSize, entry.firstAnswers.total);
      final profile = await DriftPersonalLearningProfileReader(database).load(
        ownerId: 'owner:history',
        nowUtc: when,
        timezoneId: 'Asia/Bangkok',
      );
      expect(profile.accuracy.correctCount, 5);
      expect(profile.accuracy.sampleSize, 6);
      expect(profile.mastery.observedPracticeCount, 6);
      expect(profile.engagement.totalXp, progress.totalXp);
      expect(
        profile.effort.activeDuration,
        calendar.weekly.effort.activeDuration,
      );
      expect(profile.weakness.items.single.wordId, 'first-word-5');
      expect(profile.weakness.items.single.sampleSize, 1);
      expect(profile.weakness.items.single.incorrectCount, 1);
      expect(await _sourceSnapshot(database), before);
    },
  );

  test(
    'unpinned CEFR history has truthful metadata without replay or source writes',
    () async {
      await _seedTerminalSession(
        database,
        id: 'session:local-cefr',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 11),
        endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
        configuration: _configuration(
          mode: LessonMode.cefrReading,
          itemCount: 1,
          withPack: false,
        ),
      );
      final before = await _sourceSnapshot(database);
      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history'),
      )).single;
      final presentation = entry.localCefrPresentation;
      expect(presentation, isNotNull);
      expect(presentation!.titleThai, 'กิจกรรมอ่านตามระดับ CEFR');
      expect(
        presentation.detailThai,
        'รอบนี้บันทึกการฝึกอ่านไว้ แต่ไม่ได้บันทึกชื่อบทอ่านหรือระดับที่เลือก',
      );
      expect(entry.packIdentity, isNull);
      expect(entry.packTitle, isNull);
      expect(
        entry.contentAvailability,
        LearningHistoryContentAvailability.unavailable,
      );
      await expectLater(
        reader.replayAsNewSession(
          entry.sessionId,
          replayOperationId: 'history-replay:local-cefr',
        ),
        throwsStateError,
      );
      expect(
        await reader.list(const HistoryFilter(ownerId: 'owner:other')),
        isEmpty,
      );
      expect(await _sourceSnapshot(database), before);
    },
  );

  for (final mode in [LessonMode.cefrReading, LessonMode.meaningQuiz]) {
    for (final withPack in [true, false]) {
      if (mode == LessonMode.cefrReading && !withPack) continue;
      test(
        'local CEFR metadata does not relabel ${mode.id} withPack=$withPack',
        () async {
          await _seedTerminalSession(
            database,
            id: 'session:not-local-cefr',
            state: 'completed',
            startedAtUtc: DateTime.utc(2026, 8, 31, 11),
            endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
            configuration: _configuration(
              mode: mode,
              itemCount: 1,
              withPack: withPack,
            ),
          );
          var entry = (await reader.list(
            const HistoryFilter(ownerId: 'owner:history'),
          )).single;
          expect(entry.localCefrPresentation, isNull);
          if (withPack) {
            expect(entry.packTitle, 'Travel Essentials');
            await database.delete(database.learningPacks).go();
            entry = (await reader.list(
              const HistoryFilter(ownerId: 'owner:history'),
            )).single;
            expect(entry.localCefrPresentation, isNull);
            expect(entry.packTitle, isNull);
          }
        },
      );
    }
  }

  for (final state in ['completed', 'abandoned']) {
    test('history reads $state associativeReading storage alias', () async {
      await _seedTerminalSession(
        database,
        id: 'session:association-carrier',
        state: state,
        startedAtUtc: DateTime.utc(2026, 8, 31, 11),
        endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
        configuration: _configuration(
          mode: LessonMode.associativeReading,
          itemCount: 1,
        ),
      );
      await database.customStatement(
        "UPDATE learning_sessions SET activity_type='associativeReading' WHERE id='session:association-carrier'",
      );
      final before = await _sourceSnapshot(database);
      final entries = await reader.list(
        const HistoryFilter(ownerId: 'owner:history'),
      );
      expect(entries.single.mode, LessonMode.associativeReading);
      expect(entries.single.sessionId, 'session:association-carrier');
      expect(await _sourceSnapshot(database), before);
    });
  }

  test('associativeReading alias rejects an unrelated configured mode', () async {
    await _seedTerminalSession(
      database,
      id: 'session:wrong-association-carrier',
      state: 'completed',
      startedAtUtc: DateTime.utc(2026, 8, 31, 11),
      endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
      configuration: _configuration(mode: LessonMode.dictation, itemCount: 1),
    );
    await database.customStatement(
      "UPDATE learning_sessions SET activity_type='associativeReading' WHERE id='session:wrong-association-carrier'",
    );
    await expectLater(
      reader.list(const HistoryFilter(ownerId: 'owner:history')),
      throwsStateError,
    );
  });

  for (final mode in [
    LessonMode.meaningQuiz,
    LessonMode.typedRecall,
    LessonMode.definitionQuiz,
    LessonMode.cloze,
    LessonMode.dictation,
    LessonMode.speaking,
    LessonMode.shadowing,
    LessonMode.cefrReading,
    LessonMode.sentenceScramble,
    LessonMode.wordScramble,
  ]) {
    test(
      'history reads configured ${mode.id} in the quiz storage carrier',
      () async {
        await _seedTerminalSession(
          database,
          id: 'session:quiz-carrier',
          state: 'completed',
          startedAtUtc: DateTime.utc(2026, 8, 31, 11),
          endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
          configuration: _configuration(mode: mode, itemCount: 1),
        );
        // LearningUseCases.startQuiz persists this activity type even when a
        // native vocabulary mode supplies its canonical session configuration.
        await database.customStatement(
          "UPDATE learning_sessions SET activity_type='quiz' WHERE id='session:quiz-carrier'",
        );
        final before = await _sourceSnapshot(database);
        final entries = await reader.list(
          const HistoryFilter(ownerId: 'owner:history'),
        );
        expect(entries.single.mode, mode);
        expect(entries.single.sessionId, 'session:quiz-carrier');
        expect(await _sourceSnapshot(database), before);
      },
    );
  }

  for (final mode in [
    LessonMode.matching,
    LessonMode.associativeReading,
    LessonMode.flashcard,
    LessonMode.handwritingScratchpad,
  ]) {
    test(
      'quiz carrier does not authorize unrelated ${mode.id} history',
      () async {
        await _seedTerminalSession(
          database,
          id: 'session:wrong-carrier',
          state: 'completed',
          startedAtUtc: DateTime.utc(2026, 8, 31, 11),
          endedAtUtc: DateTime.utc(2026, 8, 31, 11, 1),
          configuration: _configuration(mode: mode, itemCount: 1),
        );
        await database.customStatement(
          "UPDATE learning_sessions SET activity_type='quiz' WHERE id='session:wrong-carrier'",
        );
        await expectLater(
          reader.list(const HistoryFilter(ownerId: 'owner:history')),
          throwsStateError,
        );
      },
    );
  }

  for (final state in ['completed', 'abandoned']) {
    test(
      'candidate page merges $state assessment terminal time and stable ties before hydration',
      () async {
        const assessment = 'session:m-assessment';
        await database
            .into(database.learningSessions)
            .insert(
              LearningSessionsCompanion.insert(
                id: assessment,
                ownerId: 'owner:history',
                activityType: 'assessment',
                state: 'active',
                startedAtUtcMs: DateTime.utc(
                  2026,
                  8,
                  31,
                  9,
                ).millisecondsSinceEpoch,
                appVersion: 'test',
                buildId: 'f43',
              ),
            );
        await _seedAssessmentRun(database, sessionId: assessment);
        if (state == 'abandoned') {
          await database.customStatement(
            "UPDATE assessment_runs SET state='abandoned',abandoned_at_utc_ms=completed_at_utc_ms,completed_at_utc_ms=NULL",
          );
        }
        final configuration = _configuration(
          mode: LessonMode.meaningQuiz,
          itemCount: 1,
        );
        for (final item in [
          ('session:newest', 0, 8),
          ('session:newer-start', 1, 7),
          ('session:a-before', 0, 7),
          ('session:z-after', 0, 7),
          ('session:older', 0, 6),
        ]) {
          await _seedTerminalSession(
            database,
            id: item.$1,
            state: 'completed',
            startedAtUtc: DateTime.utc(2026, 8, 31, 9, item.$2),
            endedAtUtc: DateTime.utc(2026, 8, 31, 9, item.$3),
            configuration: configuration,
          );
        }
        final observed = _ObservedHistoryTime(
          DriftLearningTimeRepository(
            database,
            owners: const _Owners('owner:history'),
          ),
        );
        final bounded = DriftLearningHistoryReader(
          database,
          learningTime: observed,
          nowUtc: () => DateTime.utc(2026, 8, 31, 12),
        );
        const ordered = [
          'session:newest',
          'session:newer-start',
          'session:a-before',
          assessment,
          'session:z-after',
          'session:older',
        ];
        for (final limit in [1, 3, 4, 6]) {
          observed.hydrated.clear();
          final entries = await bounded.list(
            HistoryFilter(
              ownerId: 'owner:history',
              limit: limit,
              includePracticeReplay: false,
            ),
          );
          expect(entries.map((e) => e.sessionId), ordered.take(limit));
          expect(observed.hydrated, ordered.take(limit));
          if (limit >= 4) {
            expect(entries[3].assessmentSummary!.state.name, state);
          }
        }
      },
    );
  }

  test(
    'page hydrates only selected normal after newer replay batches and leaves old corruption off-page',
    () async {
      final configuration = _configuration(
        mode: LessonMode.meaningQuiz,
        itemCount: 1,
      );
      for (final name in ['old', 'recent']) {
        await _seedTerminalSession(
          database,
          id: 'session:$name',
          state: 'completed',
          startedAtUtc: DateTime.utc(2026, 8, 31, name == 'old' ? 8 : 9),
          endedAtUtc: DateTime.utc(2026, 8, 31, name == 'old' ? 8 : 9, 5),
          configuration: configuration,
        );
      }
      await _seedOrphanAnswerEvent(
        database,
        sessionId: 'session:old',
        attemptId: 'attempt:orphan-old',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 8, 2),
        evidence: EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'typed-recall',
          hintLevel: 0,
          contentRevision: 'pack:travel@1',
          engagementAllowed: false,
        ),
      );
      for (var i = 0; i < 21; i++) {
        final id = await seedSyntheticReplayPurpose(
          database,
          owner: 'owner:history',
          at: DateTime.utc(2026, 8, 31, 10, i),
          operationId: 'synthetic-page-replay-$i',
        );
        await database.customStatement(
          "UPDATE learning_sessions SET state='abandoned',ended_at_utc_ms=started_at_utc_ms WHERE id=?",
          [id],
        );
      }
      final observed = _ObservedHistoryTime(
        DriftLearningTimeRepository(
          database,
          owners: const _Owners('owner:history'),
        ),
      );
      final bounded = DriftLearningHistoryReader(
        database,
        learningTime: observed,
        nowUtc: () => DateTime.utc(2026, 8, 31, 12),
      );
      expect(
        (await bounded.list(
          const HistoryFilter(
            ownerId: 'owner:history',
            limit: 1,
            includePracticeReplay: false,
          ),
        )).single.sessionId,
        'session:recent',
      );
      expect(observed.hydrated, ['session:recent']);
      observed.hydrated.clear();
      await expectLater(
        bounded.list(
          const HistoryFilter(
            ownerId: 'owner:history',
            limit: 2,
            includePracticeReplay: false,
          ),
        ),
        throwsStateError,
      );
      expect(observed.hydrated, ['session:recent', 'session:old']);
      observed.hydrated.clear();
      expect(
        await bounded.list(
          const HistoryFilter(ownerId: 'owner:history', limit: 1),
        ),
        hasLength(1),
      );
      expect(
        observed.hydrated,
        hasLength(1),
        reason: 'default page must not hydrate lifetime history',
      );
    },
  );

  test(
    'f43 reader joins terminal sessions evidence events and active duration without mutation',
    () async {
      final olderConfiguration = _configuration(
        mode: LessonMode.typedRecall,
        itemCount: 1,
      );
      final newerConfiguration = _configuration(
        mode: LessonMode.meaningQuiz,
        itemCount: 2,
      );
      await _seedTerminalSession(
        database,
        id: 'session:older',
        state: 'abandoned',
        startedAtUtc: DateTime.utc(2026, 8, 30, 8),
        endedAtUtc: DateTime.utc(2026, 8, 30, 8, 4),
        configuration: olderConfiguration,
      );
      await _seedTerminalSession(
        database,
        id: 'session:newer',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 9),
        endedAtUtc: DateTime.utc(2026, 8, 31, 9, 7),
        configuration: newerConfiguration,
        correctCount: 1,
        wrongCount: 1,
        score: 50,
      );
      await _seedActiveSegment(
        database,
        id: 'segment:newer:1',
        sessionId: 'session:newer',
        offsetMs: 0,
        durationMs: 70000,
      );
      await _seedActiveSegment(
        database,
        id: 'segment:newer:2',
        sessionId: 'session:newer',
        offsetMs: 70000,
        durationMs: 50000,
      );
      final evidence = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'typed-recall',
        hintLevel: 0,
        contentRevision: 'pack:travel@1',
        engagementAllowed: false,
      );
      final event = await _seedAttemptAndEvent(
        database,
        sessionId: 'session:newer',
        attemptId: 'attempt:newer:1',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
        evidence: evidence,
      );
      final before = await _sourceSnapshot(database);

      final first = await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      );
      final replay = await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      );

      expect(first.map((entry) => entry.sessionId), <String>[
        'session:newer',
        'session:older',
      ]);
      expect(
        replay.map((entry) => entry.sessionId),
        first.map((entry) => entry.sessionId),
      );
      final completed = first.first;
      expect(completed.ownerId, 'owner:history');
      expect(completed.mode, LessonMode.meaningQuiz);
      expect(completed.packIdentity, _packIdentity);
      expect(completed.packTitle, 'Travel Essentials');
      expect(
        completed.contentAvailability,
        LearningHistoryContentAvailability.available,
      );
      expect(completed.activeLearningDuration, const Duration(minutes: 2));
      expect(completed.terminalState, LearningHistoryTerminalState.completed);
      expect(completed.startedAtUtc, DateTime.utc(2026, 8, 31, 9));
      expect(completed.endedAtUtc, DateTime.utc(2026, 8, 31, 9, 7));
      expect(completed.correctCount, 1);
      expect(completed.wrongCount, 1);
      expect(completed.score, 50);
      expect(completed.sessionConfiguration, newerConfiguration);
      expect(completed.evidence, hasLength(1));
      expect(completed.evidence.single.attemptId, 'attempt:newer:1');
      expect(completed.evidence.single.eventId, event.eventId);
      expect(
        completed.evidence.single.evidenceContext.toJson(),
        evidence.toJson(),
      );
      expect(completed.evidence.single.event.toJson(), event.toJson());
      expect(await _sourceSnapshot(database), before);
    },
  );

  test(
    'f43 reader uses immutable tie breakers and isolates the requested owner',
    () async {
      final configuration = _configuration(
        mode: LessonMode.flashcard,
        itemCount: 1,
      );
      final terminalAt = DateTime.utc(2026, 8, 31, 10);
      for (final id in <String>['session:b', 'session:a']) {
        await _seedTerminalSession(
          database,
          id: id,
          state: 'completed',
          startedAtUtc: terminalAt.subtract(const Duration(minutes: 1)),
          endedAtUtc: terminalAt,
          configuration: configuration,
        );
      }
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner:foreign',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session:foreign',
              ownerId: 'owner:foreign',
              activityType: LessonMode.flashcard.id,
              state: 'completed',
              startedAtUtcMs: terminalAt.millisecondsSinceEpoch,
              endedAtUtcMs: Value(terminalAt.millisecondsSinceEpoch),
              appVersion: 'test',
              buildId: 'f43',
            ),
          );

      final entries = await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 2),
      );

      expect(entries.map((entry) => entry.sessionId), <String>[
        'session:a',
        'session:b',
      ]);
    },
  );

  test(
    'f43 deleted pack keeps pinned identity and uses a safe unavailable fallback',
    () async {
      final configuration = _configuration(
        mode: LessonMode.definitionQuiz,
        itemCount: 1,
      );
      await _seedTerminalSession(
        database,
        id: 'session:deleted-pack',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 7),
        endedAtUtc: DateTime.utc(2026, 8, 31, 7, 3),
        configuration: configuration,
      );
      await database.delete(database.learningPacks).go();

      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      )).single;

      expect(entry.packIdentity, _packIdentity);
      expect(entry.packTitle, isNull);
      expect(
        entry.contentAvailability,
        LearningHistoryContentAvailability.unavailable,
      );
      expect(entry.mode, LessonMode.definitionQuiz);
      expect(entry.startedAtUtc, DateTime.utc(2026, 8, 31, 7));
      expect(entry.terminalState, LearningHistoryTerminalState.completed);
    },
  );

  test(
    'f43 history classifies answer and checkpoint events without treating checkpoints as attempts',
    () async {
      final configuration = _configuration(
        mode: LessonMode.matching,
        itemCount: 1,
      );
      await _seedTerminalSession(
        database,
        id: 'session:checkpointed',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 10),
        endedAtUtc: DateTime.utc(2026, 8, 31, 10, 5),
        configuration: configuration,
      );
      final evidence = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'matching',
        hintLevel: 0,
        contentRevision: 'pack:travel@1',
        engagementAllowed: false,
      );
      await _seedAttemptAndEvent(
        database,
        sessionId: 'session:checkpointed',
        attemptId: 'attempt:checkpointed:1',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 10, 2),
        evidence: evidence,
      );
      await _seedCheckpointEvent(
        database,
        sessionId: 'session:checkpointed',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 10, 3),
      );

      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      )).single;

      expect(entry.evidence, hasLength(1));
      expect(entry.evidence.single.attemptId, 'attempt:checkpointed:1');
      expect(entry.pairPurposeUnavailable, true);
      expect(entry.pairSummary, isNull);
      expect(
        await reader.list(
          const HistoryFilter(
            ownerId: 'owner:history',
            limit: 1,
            includePracticeReplay: false,
          ),
        ),
        isEmpty,
      );

      await _seedOrphanAnswerEvent(
        database,
        sessionId: 'session:checkpointed',
        attemptId: 'attempt:checkpointed:orphan',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 10, 4),
        evidence: evidence,
      );
      await expectLater(
        reader.list(const HistoryFilter(ownerId: 'owner:history', limit: 20)),
        throwsStateError,
        reason: 'an extra canonical answer event cannot be ignored',
      );
    },
  );

  test(
    'f43 paired answer events reject every noncanonical envelope and evidence-class correlation',
    () async {
      final corruptions = <_HistoryEventCorruption>[
        _HistoryEventCorruption('eventVersion', (db, event, attemptId) async {
          await (db.update(db.eventsV2)
                ..where((row) => row.eventId.equals(event.eventId)))
              .write(const EventsV2Companion(eventVersion: Value(99)));
        }),
        _HistoryEventCorruption('idempotencyKey', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(
              idempotencyKey: Value('learning-attempt:tampered:v2'),
            ),
          );
        }),
        _HistoryEventCorruption('aggregateType', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(aggregateType: Value('UntrustedAggregate')),
          );
        }),
        _HistoryEventCorruption('aggregateId', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(aggregateId: Value('session:unrelated')),
          );
        }),
        _HistoryEventCorruption('actorIdentity', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(actorIdentity: Value('owner:unrelated')),
          );
        }),
        _HistoryEventCorruption('ownerIdentity', (db, event, attemptId) async {
          await db
              .into(db.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'owner:unrelated',
                  createdAtUtcMs: 2,
                ),
              );
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(ownerId: Value('owner:unrelated')),
          );
        }),
        _HistoryEventCorruption('occurredAtUtc', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            EventsV2Companion(
              occurredAtUtc: Value(
                event.occurredAtUtc.add(const Duration(seconds: 1)),
              ),
            ),
          );
        }),
        _HistoryEventCorruption('recordedAtUtc', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            EventsV2Companion(
              recordedAtUtc: Value(
                event.recordedAtUtc.add(const Duration(seconds: 1)),
              ),
            ),
          );
        }),
        _HistoryEventCorruption('privacyClassification', (
          db,
          event,
          attemptId,
        ) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            EventsV2Companion(
              privacyClassification: Value(
                PrivacyClassification.restricted.name,
              ),
            ),
          );
        }),
        _HistoryEventCorruption('contentRevision', (
          db,
          event,
          attemptId,
        ) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(contentRevision: Value('content:tampered')),
          );
        }),
        _HistoryEventCorruption('policyVersion', (db, event, attemptId) async {
          await (db.update(
            db.eventsV2,
          )..where((row) => row.eventId.equals(event.eventId))).write(
            const EventsV2Companion(policyVersion: Value('policy:tampered')),
          );
        }),
        _HistoryEventCorruption('persistedEvidenceClass', (
          db,
          event,
          attemptId,
        ) async {
          await (db.update(
            db.answerAttempts,
          )..where((row) => row.id.equals(attemptId))).write(
            const AnswerAttemptsCompanion(evidenceClass: Value('recognition')),
          );
        }),
      ];
      final acceptedCorruptions = <String>[];

      for (final corruption in corruptions) {
        final caseDatabase = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwnerAndWord(caseDatabase);
          await _seedPack(caseDatabase);
          await _seedTerminalSession(
            caseDatabase,
            id: 'session:envelope',
            state: 'completed',
            startedAtUtc: DateTime.utc(2026, 8, 31, 10),
            endedAtUtc: DateTime.utc(2026, 8, 31, 10, 5),
            configuration: _configuration(
              mode: LessonMode.typedRecall,
              itemCount: 1,
            ),
          );
          const attemptId = 'attempt:envelope:1';
          final evidence = EvidenceContext.legacyCompatibility(
            evidenceClass: EvidenceClass.independentRecall,
            skillId: 'typed-recall',
            hintLevel: 0,
            contentRevision: 'pack:travel@1',
            engagementAllowed: false,
          );
          final event = await _seedAttemptAndEvent(
            caseDatabase,
            sessionId: 'session:envelope',
            attemptId: attemptId,
            occurredAtUtc: DateTime.utc(2026, 8, 31, 10, 2),
            evidence: evidence,
          );
          await corruption.apply(caseDatabase, event, attemptId);
          final caseReader = DriftLearningHistoryReader(
            caseDatabase,
            learningTime: DriftLearningTimeRepository(
              caseDatabase,
              owners: const _Owners('owner:history'),
            ),
            nowUtc: () => DateTime.utc(2026, 8, 31, 12),
          );

          try {
            await caseReader.list(
              const HistoryFilter(ownerId: 'owner:history', limit: 20),
            );
            acceptedCorruptions.add(corruption.name);
          } on Object {
            // Every malformed canonical pair must fail closed.
          }
        } finally {
          await caseDatabase.close();
        }
      }

      expect(
        acceptedCorruptions,
        isEmpty,
        reason:
            'history must consume the complete canonical answer-envelope contract',
      );
    },
  );

  test(
    'f43 history includes terminal assessment outcome without exposing research assignment or consent authority',
    () async {
      const sessionId = 'session:assessment-history';
      final startedAtUtc = DateTime.utc(2026, 8, 31, 9);
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: sessionId,
              ownerId: 'owner:history',
              activityType: 'assessment',
              state: 'active',
              startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
              appVersion: 'test',
              buildId: 'f43',
            ),
          );
      final run = await _seedAssessmentRun(database, sessionId: sessionId);

      final entries = await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      );

      expect(entries, hasLength(1));
      final dynamic entry = entries.single;
      expect(entry.localCefrPresentation, isNull);
      expect(
        () => entry.assessmentRun,
        throwsA(isA<NoSuchMethodError>()),
        reason: 'presentation must not expose the research authority object',
      );
      final dynamic summary = entry.assessmentSummary;
      expect(
        entry.contentAvailability,
        LearningHistoryContentAvailability.unavailable,
        reason: 'assessment history has no lesson replay authority',
      );
      expect(summary.phase, run.phase);
      expect(summary.state, run.state);
      expect(summary.terminalAtUtc, run.completedAtUtc);
      expect(() => summary.assignmentId, throwsA(isA<NoSuchMethodError>()));
      expect(() => summary.cohort, throwsA(isA<NoSuchMethodError>()));
      expect(() => summary.consentVersion, throwsA(isA<NoSuchMethodError>()));
    },
  );

  test(
    'f43 assessment summary rejects generic mismatched and out-of-interval evidence',
    () async {
      final cases = <_AssessmentHistoryEvidenceCase>[
        _AssessmentHistoryEvidenceCase(
          name: 'canonical',
          shouldSucceed: true,
          build: (run) {
            final evidence = _assessmentEvidence(run);
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'genericEvidenceClass',
          shouldSucceed: false,
          build: (run) {
            final evidence = EvidenceContext.legacyCompatibility(
              evidenceClass: EvidenceClass.independentRecall,
              skillId: 'typed-recall',
              hintLevel: 0,
              contentRevision: 'pack:travel@1',
              engagementAllowed: false,
            );
            return (
              evidence: evidence,
              eventContext: LearningEventContext.noResearch(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'protocolMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run, protocolVersion: '2.0.0');
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'experimentMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(
              run,
              experimentId: 'experiment:unrelated',
            );
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'assignmentMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(
              run,
              assignmentId: 'assignment:unrelated',
            );
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'cohortMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run, cohort: 'shadow');
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'consentMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run, consentVersion: 2);
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'instrumentMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run, instrumentVersion: '2');
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'formMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run, formVersion: '2');
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'contentRevisionMismatch',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(
              run,
              contentRevision: 'assessment:unrelated@1',
            );
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 2),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'beforeRun',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run);
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 8, 59),
            );
          },
        ),
        _AssessmentHistoryEvidenceCase(
          name: 'afterTerminal',
          shouldSucceed: false,
          build: (run) {
            final evidence = _assessmentEvidence(run);
            return (
              evidence: evidence,
              eventContext: _assessmentEventContext(evidence),
              occurredAtUtc: DateTime.utc(2026, 8, 31, 9, 8),
            );
          },
        ),
      ];
      final acceptedInvalidEvidence = <String>[];

      for (final evidenceCase in cases) {
        final caseDatabase = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwnerAndWord(caseDatabase);
          const sessionId = 'session:assessment-evidence';
          await caseDatabase
              .into(caseDatabase.learningSessions)
              .insert(
                LearningSessionsCompanion.insert(
                  id: sessionId,
                  ownerId: 'owner:history',
                  activityType: 'assessment',
                  state: 'active',
                  startedAtUtcMs: DateTime.utc(
                    2026,
                    8,
                    31,
                    9,
                  ).millisecondsSinceEpoch,
                  appVersion: 'test',
                  buildId: 'f43',
                ),
              );
          final run = await _seedAssessmentRun(
            caseDatabase,
            sessionId: sessionId,
          );
          final fixture = evidenceCase.build(run);
          await _seedAttemptAndEvent(
            caseDatabase,
            sessionId: sessionId,
            attemptId: 'attempt:assessment:1',
            occurredAtUtc: fixture.occurredAtUtc,
            evidence: fixture.evidence,
            learningEventContext: fixture.eventContext,
          );
          final caseReader = DriftLearningHistoryReader(
            caseDatabase,
            learningTime: DriftLearningTimeRepository(
              caseDatabase,
              owners: const _Owners('owner:history'),
            ),
            nowUtc: () => DateTime.utc(2026, 8, 31, 12),
          );

          Object? failure;
          List<LearningHistoryEntry>? entries;
          try {
            entries = await caseReader.list(
              const HistoryFilter(ownerId: 'owner:history', limit: 20),
            );
          } on Object catch (error) {
            failure = error;
          }
          if (evidenceCase.shouldSucceed) {
            expect(failure, isNull, reason: evidenceCase.name);
            expect(entries, hasLength(1), reason: evidenceCase.name);
            final canonicalEntries = entries!;
            expect(canonicalEntries.single.assessmentSummary!.sampleSize, 1);
            expect(canonicalEntries.single.assessmentSummary!.correctCount, 1);
          } else if (failure == null) {
            acceptedInvalidEvidence.add(evidenceCase.name);
          }
        } finally {
          await caseDatabase.close();
        }
      }

      expect(
        acceptedInvalidEvidence,
        isEmpty,
        reason:
            'assessment history must validate exact run pins and time bounds before summarizing',
      );
    },
  );

  test(
    'f43 legacy and unpinned terminal sessions render safe unavailable metadata and cannot replay',
    () async {
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session:legacy-unpinned',
              ownerId: 'owner:history',
              activityType: LessonMode.typedRecall.id,
              state: 'completed',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                31,
                6,
              ).millisecondsSinceEpoch,
              endedAtUtcMs: Value(
                DateTime.utc(2026, 8, 31, 6, 4).millisecondsSinceEpoch,
              ),
              correctCount: const Value(1),
              appVersion: 'legacy',
              buildId: 'legacy-build',
            ),
          );

      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      )).single;

      expect(entry.mode, LessonMode.typedRecall);
      expect(entry.packIdentity, isNull);
      expect(entry.packTitle, isNull);
      expect(entry.sessionConfiguration, isNull);
      expect(entry.localCefrPresentation, isNull);
      expect(
        entry.contentAvailability,
        LearningHistoryContentAvailability.unavailable,
      );
      await expectLater(
        reader.replayAsNewSession(
          entry.sessionId,
          replayOperationId: 'history-replay:legacy-unpinned',
        ),
        throwsStateError,
      );
      await database.customStatement(
        "UPDATE learning_sessions SET activity_type='cefr-reading' WHERE id='session:legacy-unpinned'",
      );
      final unconfiguredCefr = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history'),
      )).single;
      expect(unconfiguredCefr.sessionConfiguration, isNull);
      expect(unconfiguredCefr.mode, LessonMode.cefrReading);
      expect(unconfiguredCefr.localCefrPresentation, isNull);
    },
  );

  test(
    'f43 exact frozen-v13 paired evidence renders immutable unavailable history without replay',
    () async {
      const sessionId = 'session:frozen-v13-history';
      const attemptId = 'attempt:frozen-v13-history:1';
      final occurredAtUtc = DateTime.utc(2026, 8, 31, 6, 2);
      final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: sessionId,
              ownerId: 'owner:history',
              activityType: LessonMode.typedRecall.id,
              state: 'completed',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                31,
                6,
              ).millisecondsSinceEpoch,
              endedAtUtcMs: Value(
                DateTime.utc(2026, 8, 31, 6, 4).millisecondsSinceEpoch,
              ),
              correctCount: const Value(1),
              appVersion: 'legacy',
              buildId: 'legacy-build',
            ),
          );
      await database
          .into(database.answerAttempts)
          .insert(
            AnswerAttemptsCompanion.insert(
              id: attemptId,
              ownerId: 'owner:history',
              sessionId: sessionId,
              wordId: 'word:station',
              promptMode: 'typedRecall',
              isCorrect: true,
              responseTimeMs: const Value(900),
              attemptNumber: 1,
              occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
              evidenceClass: Value(context.evidenceClass.name),
              evidenceContextJson: Value(jsonEncode(context.toJson())),
            ),
          );
      final eventId = LearningEvidenceContract.learningEventId(attemptId);
      await database
          .into(database.eventsV2)
          .insert(
            EventsV2Companion.insert(
              eventId: eventId,
              eventType: 'QuizCompleted',
              eventVersion: 1,
              occurredAtUtc: occurredAtUtc,
              recordedAtUtc: occurredAtUtc,
              actorIdentity: 'owner:history',
              ownerId: 'owner:history',
              aggregateType: 'LearningSession',
              aggregateId: sessionId,
              idempotencyKey: 'learning-attempt:$attemptId:v1',
              consentContextJson: jsonEncode(
                const ConsentContext.none().toJson(),
              ),
              appVersion: 'legacy',
              buildId: 'legacy-build',
              privacyClassification: PrivacyClassification.anonymized.name,
              payloadJson: jsonEncode(<String, Object?>{
                'attemptId': attemptId,
              }),
            ),
          );
      final before = await _sourceSnapshot(database);

      final entry = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      )).single;

      expect(entry.sessionId, sessionId);
      expect(entry.sessionConfiguration, isNull);
      expect(
        entry.contentAvailability,
        LearningHistoryContentAvailability.unavailable,
      );
      expect(entry.evidence, hasLength(1));
      expect(entry.evidence.single.attemptId, attemptId);
      expect(entry.evidence.single.event.eventVersion, 1);
      expect(entry.evidence.single.event.payload, const <String, Object?>{
        'attemptId': attemptId,
      });
      expect(
        () => entry.evidence.single.event.payload['attemptId'] = 'tampered',
        throwsUnsupportedError,
      );
      await expectLater(
        reader.replayAsNewSession(
          sessionId,
          replayOperationId: 'history-replay:frozen-v13',
        ),
        throwsStateError,
      );
      expect(await _sourceSnapshot(database), before);
    },
  );

  test(
    'f43 history rejects noncontiguous active-time rows through the canonical time authority',
    () async {
      final configuration = _configuration(
        mode: LessonMode.meaningQuiz,
        itemCount: 1,
      );
      await _seedTerminalSession(
        database,
        id: 'session:invalid-time',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 11),
        endedAtUtc: DateTime.utc(2026, 8, 31, 11, 10),
        configuration: configuration,
      );
      await _seedActiveSegment(
        database,
        id: 'segment:invalid-time:1',
        sessionId: 'session:invalid-time',
        offsetMs: 1000,
        durationMs: 1000,
      );

      await expectLater(
        reader.list(const HistoryFilter(ownerId: 'owner:history', limit: 20)),
        throwsStateError,
      );
    },
  );

  test(
    'f43 returned event evidence is deeply immutable across outer and nested payload mutation attempts',
    () async {
      final configuration = _configuration(
        mode: LessonMode.typedRecall,
        itemCount: 1,
      );
      await _seedTerminalSession(
        database,
        id: 'session:immutable-event',
        state: 'completed',
        startedAtUtc: DateTime.utc(2026, 8, 31, 12),
        endedAtUtc: DateTime.utc(2026, 8, 31, 12, 5),
        configuration: configuration,
      );
      final evidence = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'typed-recall',
        hintLevel: 0,
        contentRevision: 'pack:travel@1',
        engagementAllowed: false,
      );
      await _seedAttemptAndEvent(
        database,
        sessionId: 'session:immutable-event',
        attemptId: 'attempt:immutable-event:1',
        occurredAtUtc: DateTime.utc(2026, 8, 31, 12, 2),
        evidence: evidence,
      );

      final item = (await reader.list(
        const HistoryFilter(ownerId: 'owner:history', limit: 20),
      )).single.evidence.single;
      final canonical = jsonEncode(item.event.toJson());

      expect(item.event, isNot(isA<EventEnvelopeV2>()));
      expect(
        () => item.event.payload['correct'] = false,
        throwsUnsupportedError,
      );
      final nested = item.event.payload['evidenceContext']! as Map;
      expect(() => nested['skillId'] = 'tampered', throwsUnsupportedError);
      expect(jsonEncode(item.event.toJson()), canonical);
    },
  );

  test('f43 current schema has no learning history authority table', () async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .get();

    expect(
      rows.map((row) => row.read<String>('name')),
      isNot(contains('learning_history')),
    );
    expect(
      rows.map((row) => row.read<String>('name')),
      isNot(contains('learning_history_entries')),
    );
  });
}

typedef _HistoryEventCorruptionApply =
    Future<void> Function(
      AppDatabase database,
      EventEnvelopeV2 event,
      String attemptId,
    );

final class _HistoryEventCorruption {
  const _HistoryEventCorruption(this.name, this.apply);

  final String name;
  final _HistoryEventCorruptionApply apply;
}

typedef _AssessmentHistoryEvidenceFixture = ({
  EvidenceContext evidence,
  LearningEventContext eventContext,
  DateTime occurredAtUtc,
});

final class _AssessmentHistoryEvidenceCase {
  const _AssessmentHistoryEvidenceCase({
    required this.name,
    required this.shouldSucceed,
    required this.build,
  });

  final String name;
  final bool shouldSucceed;
  final _AssessmentHistoryEvidenceFixture Function(AssessmentRun run) build;
}

final class _Owners implements LocalOwnerRepository {
  const _Owners(this.ownerId);

  final String ownerId;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026, 8, 31));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

const _packIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:travel',
  revision: 1,
);

SessionConfiguration _configuration({
  required LessonMode mode,
  required int itemCount,
  bool withPack = true,
}) => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'owner:history',
  mode: mode,
  itemCount: itemCount,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.untimedAlternative(
    maximumActiveEffort: Duration(minutes: 10),
  ),
  packIdentity: withPack ? _packIdentity : null,
  protocolId: 'protocol:local-standard',
  protocolVersion: '1',
  protocolLimitsIdentity:
      const SessionConfigurationProtocolLimits.standard().contentIdentity,
);

Future<void> _seedOwnerAndWord(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'owner:history', createdAtUtcMs: 1),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:history',
          ownerId: 'owner:history',
          name: 'History',
          normalizedName: 'history',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:station',
          ownerId: 'owner:history',
          categoryId: 'category:history',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _seedPack(AppDatabase database) async {
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'manifest:pack:travel:r1',
          contentType: ContentType.learningPack.name,
          contentId: _packIdentity.id,
          revision: _packIdentity.revision,
          checksumSha256: 'a' * 64,
          byteLength: 1,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'asset://learning-packs/pack-travel-r1.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: 1,
          reviewedAtUtcMs: const Value(2),
          publishedAtUtcMs: const Value(3),
        ),
      );
  await database
      .into(database.learningPacks)
      .insert(
        LearningPacksCompanion.insert(
          id: 'pack:travel:r1',
          packId: _packIdentity.id,
          revision: _packIdentity.revision,
          manifestId: 'manifest:pack:travel:r1',
          title: 'Travel Essentials',
          cefrLevel: 'A1',
          topic: 'travel',
          skill: 'vocabulary',
          goal: 'recognition',
          createdAtUtcMs: 1,
        ),
      );
}

Future<void> _seedTerminalSession(
  AppDatabase database, {
  required String id,
  required String state,
  required DateTime startedAtUtc,
  required DateTime endedAtUtc,
  required SessionConfiguration configuration,
  int correctCount = 0,
  int wrongCount = 0,
  int? score,
}) => database
    .into(database.learningSessions)
    .insert(
      LearningSessionsCompanion.insert(
        id: id,
        ownerId: 'owner:history',
        activityType: configuration.mode.id,
        state: state,
        startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
        endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
        correctCount: Value(correctCount),
        wrongCount: Value(wrongCount),
        score: Value(score),
        appVersion: 'test',
        buildId: 'f43',
        sessionConfigurationIdentity: Value(configuration.contentIdentity),
        sessionConfigurationJson: Value(configuration.stableSerialization),
      ),
    );

Future<void> _seedActiveSegment(
  AppDatabase database, {
  required String id,
  required String sessionId,
  required int offsetMs,
  required int durationMs,
}) => database
    .into(database.learningTimeSegments)
    .insert(
      LearningTimeSegmentsCompanion.insert(
        id: id,
        ownerId: 'owner:history',
        sessionId: sessionId,
        activeStartOffsetMs: offsetMs,
        activeDurationMs: durationMs,
        startedAtUtcMs: DateTime.utc(
          2026,
          8,
          31,
          9,
        ).add(Duration(milliseconds: offsetMs)).millisecondsSinceEpoch,
        endedAtUtcMs: DateTime.utc(2026, 8, 31, 9)
            .add(Duration(milliseconds: offsetMs + durationMs))
            .millisecondsSinceEpoch,
        timezoneId: 'Asia/Bangkok',
        timezoneOffsetMinutes: 420,
        captureSource: 'automaticLesson',
      ),
    );

Future<EventEnvelopeV2> _seedAttemptAndEvent(
  AppDatabase database, {
  required String sessionId,
  String wordId = 'word:station',
  bool isCorrect = true,
  int attemptNumber = 1,
  required String attemptId,
  required DateTime occurredAtUtc,
  required EvidenceContext evidence,
  LearningEventContext? learningEventContext,
}) async {
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: 'owner:history',
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'typedRecall',
          isCorrect: isCorrect,
          responseTimeMs: const Value(900),
          attemptNumber: attemptNumber,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: Value(evidence.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(evidence.toJson())),
        ),
      );
  final event = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'f43')
      .adaptFromCommand(
        sourceEvidenceId: attemptId,
        ownerId: 'owner:history',
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'typedRecall',
        isCorrect: isCorrect,
        attemptNumber: attemptNumber,
        occurredAtUtc: occurredAtUtc,
        evidenceContext: evidence,
        learningEventContext:
            learningEventContext ?? LearningEventContext.noResearch(evidence),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: event.eventId,
          eventType: event.eventType,
          eventVersion: event.eventVersion,
          occurredAtUtc: event.occurredAtUtc,
          recordedAtUtc: event.recordedAtUtc,
          actorIdentity: event.actorIdentity,
          ownerId: event.ownerIdentity,
          aggregateType: event.aggregateType,
          aggregateId: event.aggregateId,
          idempotencyKey: event.idempotencyKey,
          consentContextJson: jsonEncode(event.consentContext.toJson()),
          experimentContextJson: Value(
            event.experimentContext == null
                ? null
                : jsonEncode(event.experimentContext!.toJson()),
          ),
          contentRevision: Value(event.contentRevision),
          policyVersion: Value(event.policyVersion),
          appVersion: event.appVersion,
          buildId: event.buildId,
          privacyClassification: event.privacyClassification.name,
          payloadJson: jsonEncode(event.payload),
        ),
      );
  return event;
}

Future<void> _seedOrphanAnswerEvent(
  AppDatabase database, {
  required String sessionId,
  required String attemptId,
  required DateTime occurredAtUtc,
  required EvidenceContext evidence,
}) async {
  final event = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'f43')
      .adaptFromCommand(
        sourceEvidenceId: attemptId,
        ownerId: 'owner:history',
        sessionId: sessionId,
        wordId: 'word:station',
        promptMode: 'typedRecall',
        isCorrect: true,
        attemptNumber: 1,
        occurredAtUtc: occurredAtUtc,
        evidenceContext: evidence,
        learningEventContext: LearningEventContext.noResearch(evidence),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: event.eventId,
          eventType: event.eventType,
          eventVersion: event.eventVersion,
          occurredAtUtc: event.occurredAtUtc,
          recordedAtUtc: event.recordedAtUtc,
          actorIdentity: event.actorIdentity,
          ownerId: event.ownerIdentity,
          aggregateType: event.aggregateType,
          aggregateId: event.aggregateId,
          idempotencyKey: event.idempotencyKey,
          consentContextJson: jsonEncode(event.consentContext.toJson()),
          contentRevision: Value(event.contentRevision),
          policyVersion: Value(event.policyVersion),
          appVersion: event.appVersion,
          buildId: event.buildId,
          privacyClassification: event.privacyClassification.name,
          payloadJson: jsonEncode(event.payload),
        ),
      );
}

Future<void> _seedCheckpointEvent(
  AppDatabase database, {
  required String sessionId,
  required DateTime occurredAtUtc,
}) => database
    .into(database.eventsV2)
    .insert(
      EventsV2Companion.insert(
        eventId: 'learning-activity-checkpoint:$sessionId:1',
        eventType: 'LearningActivityCheckpoint',
        eventVersion: 2,
        occurredAtUtc: occurredAtUtc,
        recordedAtUtc: occurredAtUtc,
        actorIdentity: 'owner:history',
        ownerId: 'owner:history',
        aggregateType: 'LearningSession',
        aggregateId: sessionId,
        idempotencyKey: 'learning-activity-checkpoint:$sessionId:1',
        consentContextJson: jsonEncode(const ConsentContext.none().toJson()),
        appVersion: 'test',
        buildId: 'f43',
        privacyClassification: PrivacyClassification.ownerOnly.name,
        payloadJson: jsonEncode(<String, Object?>{
          'schemaVersion': 2,
          'activityType': LessonMode.matching.id,
          'sessionId': sessionId,
          'revision': 1,
          'state': <String, Object?>{'schemaVersion': 1},
          'terminalAtUtc': occurredAtUtc.toIso8601String(),
          'terminalAcknowledged': true,
        }),
      ),
    );

Future<Map<String, Object?>> _sourceSnapshot(
  AppDatabase database,
) async => <String, Object?>{
  'sessions': [
    for (final row in await database.select(database.learningSessions).get())
      row.toJson(),
  ],
  'attempts': [
    for (final row in await database.select(database.answerAttempts).get())
      row.toJson(),
  ],
  'events': [
    for (final row in await database.select(database.eventsV2).get())
      row.toJson(),
  ],
  'segments': [
    for (final row
        in await database.select(database.learningTimeSegments).get())
      row.toJson(),
  ],
  'assessmentRuns': [
    for (final row in await database.select(database.assessmentRuns).get())
      row.toJson(),
  ],
};

Future<AssessmentRun> _seedAssessmentRun(
  AppDatabase database, {
  required String sessionId,
}) async {
  final assignedAtUtc = DateTime.utc(2026, 8, 31, 8, 55);
  await database
      .into(database.experimentAssignments)
      .insert(
        ExperimentAssignmentsCompanion.insert(
          id: 'assignment:history',
          ownerId: 'owner:history',
          experimentId: 'experiment:history',
          experimentVersion: 1,
          cohort: 'enforced',
          protocolVersion: '1.0.0',
          assignedAtUtcMs: assignedAtUtc.millisecondsSinceEpoch,
        ),
      );
  final run = AssessmentRun(
    id: 'assessment:history',
    ownerId: 'owner:history',
    learningSessionId: sessionId,
    studyCycleId: 'cycle:history',
    phase: AssessmentPhase.pre,
    state: AssessmentRunState.completed,
    protocolId: 'protocol:history',
    protocolVersion: '1.0.0',
    experimentId: 'experiment:history',
    experimentVersion: 1,
    assignmentId: 'assignment:history',
    cohort: 'enforced',
    consentVersion: 1,
    consentDecidedAtUtc: DateTime.utc(2026, 8, 31, 8, 50),
    instrumentId: 'instrument:history',
    instrumentVersion: '1',
    formId: 'form:history',
    formVersion: '1',
    instrumentChecksumSha256: 'b' * 64,
    formChecksumSha256: 'c' * 64,
    appVersion: 'test',
    buildId: 'f43',
    databaseSchemaVersion: AppDatabase.currentSchemaVersion,
    contentRevision: 'assessment:history@1',
    evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
    featureContractRevision: currentFeatureContractIdentity.revision,
    featureContractHash: currentFeatureContractIdentity.semanticHash,
    startedAtUtc: DateTime.utc(2026, 8, 31, 9),
    completedAtUtc: DateTime.utc(2026, 8, 31, 9, 7),
    abandonedAtUtc: null,
  );
  await database
      .into(database.assessmentRuns)
      .insert(
        AssessmentRunsCompanion.insert(
          id: run.id,
          ownerId: run.ownerId,
          learningSessionId: run.learningSessionId,
          studyCycleId: run.studyCycleId,
          phase: run.phase.name,
          state: run.state.name,
          protocolId: run.protocolId,
          protocolVersion: run.protocolVersion,
          experimentId: run.experimentId,
          experimentVersion: run.experimentVersion,
          assignmentId: run.assignmentId,
          cohort: run.cohort,
          consentVersion: run.consentVersion,
          consentDecidedAtUtcMs: run.consentDecidedAtUtc.millisecondsSinceEpoch,
          instrumentId: run.instrumentId,
          instrumentVersion: run.instrumentVersion,
          formId: run.formId,
          formVersion: run.formVersion,
          instrumentChecksumSha256: run.instrumentChecksumSha256,
          formChecksumSha256: run.formChecksumSha256,
          appVersion: run.appVersion,
          buildId: run.buildId,
          databaseSchemaVersion: run.databaseSchemaVersion,
          contentRevision: run.contentRevision,
          evidencePolicyVersion: run.evidencePolicyVersion,
          featureContractRevision: run.featureContractRevision,
          featureContractHash: run.featureContractHash,
          startedAtUtcMs: run.startedAtUtc.millisecondsSinceEpoch,
          completedAtUtcMs: Value(run.completedAtUtc!.millisecondsSinceEpoch),
        ),
      );
  return run;
}

EvidenceContext _assessmentEvidence(
  AssessmentRun run, {
  String? protocolVersion,
  String? experimentId,
  String? assignmentId,
  String? cohort,
  int? consentVersion,
  String? instrumentVersion,
  String? formVersion,
  String? contentRevision,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment',
  hintLevel: 0,
  contentRevision: contentRevision ?? run.contentRevision,
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: run.protocolId,
  protocolVersion: protocolVersion ?? run.protocolVersion,
  experimentId: experimentId ?? run.experimentId,
  experimentVersion: run.experimentVersion,
  assignmentId: assignmentId ?? run.assignmentId,
  cohort: cohort ?? run.cohort,
  researchConsentVersion: consentVersion ?? run.consentVersion,
  instrumentId: run.instrumentId,
  instrumentVersion: instrumentVersion ?? run.instrumentVersion,
  formId: run.formId,
  formVersion: formVersion ?? run.formVersion,
  assessmentItemId: 'item:history',
  assessmentResponseCode: 'correct',
  scoringRuleVersion: 'score-v1',
  engagementAllowed: false,
);

LearningEventContext _assessmentEventContext(EvidenceContext evidence) =>
    LearningEventContext(
      consentContext: ConsentContext(
        researchConsentVersion: evidence.researchConsentVersion!,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: evidence.experimentId!,
        variantId: evidence.cohort!,
        assignedAtUtc: DateTime.utc(2026, 8, 31, 8, 55),
      ),
      protocolId: evidence.protocolId,
      protocolVersion: evidence.protocolVersion,
      experimentVersion: evidence.experimentVersion,
      assignmentId: evidence.assignmentId,
      featureContractIdentity: currentFeatureContractIdentity,
    );
