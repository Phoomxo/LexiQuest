import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/review_ladder.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  Future<void> withDesk(
    WidgetTester tester,
    Future<void> Function(AppDatabase database, AnswerAttempt previousAttempt)
    run, {
    FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final now = DateTime.utc(2026, 11, 15, 12);
    final earlier = now.subtract(const Duration(days: 2));
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-ladder-owner-a',
      nowUtc: () => now,
    );
    var nextId = 0;
    String generatedId() => 'synthetic-ladder-${++nextId}';
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: generatedId,
      nowUtc: () => now,
    );
    final repository = DriftLearningRepository(database);
    const build = AppBuildInfo(version: 'test', buildId: 'test');
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: generatedId,
      nowUtc: () => now,
      buildInfo: build,
    );

    try {
      final previousAttempt = (await tester.runAsync(() async {
        final owner = await owners.getOrCreateActiveOwner();
        final category = await vocabulary.createCategory('การเดินทาง');
        final station = await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
        );
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'platform',
            meaning: 'ชานชาลา',
            partOfSpeech: 'noun',
          ),
        );
        const sessionId = 'synthetic-completed-srs-review';
        await repository.startSession(
          LearningSessionDraft(
            id: sessionId,
            ownerId: owner.id,
            activityType: 'srsReview',
            startedAtUtc: earlier,
            appVersion: build.version,
            buildId: build.buildId,
          ),
        );
        await learning.recordAnswer(
          sessionId: sessionId,
          wordId: station.id,
          promptMode: 'srsRecall',
          isCorrect: false,
          responseTimeMs: null,
          attemptNumber: 1,
          attemptId: 'synthetic-station-srs-attempt',
          occurredAtUtc: earlier.add(const Duration(seconds: 1)),
          expectedOwnerId: owner.id,
          srsRecallSnapshot: (
            spelling: station.spelling,
            meaning: station.meaning,
            partOfSpeech: station.partOfSpeech,
          ),
        );
        final summary = await repository.finishSession(
          ownerId: owner.id,
          sessionId: sessionId,
          endedAtUtc: earlier.add(const Duration(seconds: 2)),
        );
        expect(summary.state, 'completed');
        return database.select(database.answerAttempts).getSingle();
      }))!;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _GuestSession(),
            database: database,
            localOwners: owners,
            features: features,
            vocabulary: vocabulary,
            learning: learning,
            progress: ProgressUseCases(
              owners: owners,
              queries: DriftProgressQueries(database),
              nowUtc: () => now,
            ),
          ),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const CategoriesPage(),
          ),
        ),
      );

      await _waitFor(tester, find.text('การเดินทาง'));
      await _tap(tester, 'ทบทวนคำศัพท์');
      await _waitFor(tester, find.text('เลือกสิ่งที่จะทบทวน'));
      await run(database, previousAttempt);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(database.close);
    }
  }

  testWidgets('Library review ladder keeps assisted practice separate', (
    tester,
  ) async {
    Future<void> tap(String label) => _tap(tester, label);
    await withDesk(tester, (database, previousAttempt) async {
      final ownerId = previousAttempt.ownerId;
      final stationId = previousAttempt.wordId;
      await tap('ฝึกให้จำได้ด้วยตัวเอง');
      await tap('ลองเลือกความหมาย');
      await tap('ชานชาลา');
      await _waitFor(tester, find.text('ลองเทียบสองคำนี้'));
      await tap('ลองเลือกความหมายอีกครั้ง');
      await tap('สถานี');
      await tap('ลองนึกคำโดยไม่มีตัวเลือก');
      await _waitFor(tester, find.text('Meet me at the ____ tomorrow.'));
      final field = find.byType(TextField);
      await _waitFor(tester, field);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'station');
      await tap('ตรวจคำตอบ');
      const completed = 'คุณเลือกความหมายได้ก่อนนึกคำจากประโยค';
      await _waitFor(tester, find.text(completed));
      await tap('กลับไปเลือกสิ่งที่จะทบทวน');
      await _waitFor(tester, find.text('เลือกสิ่งที่จะทบทวน'));
      await tap('ดูผลรอบล่าสุด');
      await _waitFor(tester, find.text(completed));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        final sessions = await database.select(database.learningSessions).get();
        expect(sessions, hasLength(2));
        final ladder = sessions.singleWhere(
          (row) => row.activityType == 'reviewLadder',
        );
        expect(ladder.ownerId, ownerId);
        expect(ladder.state, 'completed');
        expect(ladder.correctCount, 0);
        expect(ladder.wrongCount, 1);
        expect(ladder.score, 0);
        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(2));
        expect(
          attempts.singleWhere((row) => row.id == previousAttempt.id),
          previousAttempt,
        );
        final first = attempts.singleWhere((row) => row.sessionId == ladder.id);
        expect(first.ownerId, ownerId);
        expect(first.wordId, stationId);
        expect(first.promptMode, 'meaningChoice');
        expect(first.isCorrect, isFalse);
        expect(first.attemptNumber, 1);
        final evidence = decodeReviewLadderRound(
          ladder.continuationJson!,
          sessionId: ladder.id,
        );
        expect(evidence.phase, ReviewLadderPhase.result);
        expect(evidence.pair.target.id, stationId);
        expect(evidence.pair.contrast.spelling, 'platform');
        expect(evidence.pair.reviewAttemptId, previousAttempt.id);
        expect(
          evidence.meaningChecks.map((check) => (check.option, check.assisted)),
          [(0, false), (1, true)],
        );
        expect(
          first.occurredAtUtcMs,
          evidence.independentChoice!.checkedAtUtc.millisecondsSinceEpoch,
        );
        expect(evidence.typedCheck?.text, 'station');
        expect(evidence.typedCheck?.assisted, isFalse);
        expect(evidence.typedCorrect, isTrue);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
        expect(await database.select(database.eventsV2).get(), isEmpty);
        expect(await database.select(database.researchConsents).get(), isEmpty);
      });
    });
  });

  testWidgets('Review Desk hides a child activity on owner switch', (
    tester,
  ) async {
    await withDesk(tester, (database, previousAttempt) async {
      await _tap(tester, 'คำที่ยังสับสน');
      await _waitFor(tester, find.text('ฝึกจุดอ่อน'));
      final privateWord = find.text('station');
      final privateDetails = find.textContaining('สถานี\nตอบผิด');
      await _waitFor(tester, privateWord);
      expect(privateDetails, findsOneWidget);

      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(previousAttempt.ownerId)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'synthetic-ladder-owner-b',
                createdAtUtcMs: 1,
              ),
            );
      });
      await _waitFor(tester, privateWord, disappears: true);
      expect(privateDetails, findsNothing);
    });
  });

  testWidgets('Review Desk respects hidden quiz', (tester) async {
    await withDesk(
      tester,
      (_, _) async {
        await _waitFor(tester, find.text('ฝึกด้วยบัตรคำ'));
        expect(find.text('ฝึกให้จำได้ด้วยตัวเอง'), findsNothing);
        await _tap(tester, 'คำที่ยังสับสน');
        await _waitFor(tester, find.text('ฝึกจุดอ่อน'));
        await _waitFor(tester, find.text('station'));
        expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
      },
      features: const BuildFeatureRegistry({
        Feature.vocabulary: FeatureState.enabled,
        Feature.srs: FeatureState.enabled,
        Feature.weakness: FeatureState.enabled,
        Feature.quiz: FeatureState.hidden,
      }),
    );
  });
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await _waitFor(tester, target);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.ensureVisible(target.first);
  await tester.tap(target.first);
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder target, {
  bool disappears = false,
}) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isEmpty == disappears) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail(
    'Timed out waiting for $target to ${disappears ? 'disappear' : 'appear'}. '
    'Current text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
  );
}

final class _GuestSession extends Fake implements GuestSessionService {}
