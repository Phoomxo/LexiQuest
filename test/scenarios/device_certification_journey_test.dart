import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:uuid/uuid.dart';

/// Scenario tests that simulate real user journeys for device certification.
/// These are NOT integration tests (no Firebase/device) — they verify the
/// data-layer pipeline that underpins every certification scenario.
void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late VocabularyUseCases vocabulary;
  late LearningUseCases learning;
  late RewardUseCases rewards;
  late UpgradeGuestOwner upgrade;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final idGen = const Uuid().v4;
    DateTime now() => DateTime.now().toUtc();
    owners = DriftLocalOwnerRepository(
      database,
      generateId: idGen,
      nowUtc: now,
    );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: idGen,
      nowUtc: now,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: idGen,
      nowUtc: now,
      buildInfo: const AppBuildInfo.fromEnvironment(),
    );
    rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: idGen,
      nowUtc: now,
    );
    upgrade = UpgradeGuestOwner(
      DriftOwnerUpgradeRepository(
        database,
        nowUtc: now,
        generateConflictId: idGen,
        generateOwnerId: idGen,
      ),
    );
  });

  tearDown(() => database.close());

  group('Device Certification Scenarios', () {
    test('S1: Guest can create vocabulary and record answers offline', () async {
      // ── Guest starts locally (no Firebase) ────────────────────────────
      final owner = await owners.getOrCreateActiveOwner();
      expect(owner.id, startsWith('local:'));

      // ── Create category + words ───────────────────────────────────────
      final category = await vocabulary.createCategory('Travel');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'station',
          meaning: 'สถานี',
          partOfSpeech: 'noun',
          cefrLevel: 'A2',
        ),
      );

      final words = await vocabulary.getGameWords(limit: 5);
      expect(words.length, 1);
      expect(words.first.spelling, 'station');
      expect(words.first.cefrLevel, 'A2');

      // ── Start quiz and record answer ──────────────────────────────────
      final session = await learning.startQuiz();
      expect(session.questions, isNotEmpty);

      await learning.recordAnswer(
        sessionId: session.id,
        wordId: session.questions.first.word.id,
        promptMode: 'quiz',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
      );

      // ── Finish session ────────────────────────────────────────────────
      final result = await learning.finishSession(session.id);
      expect(result.correctCount, greaterThan(0));
    });

    test('S2: Session resume — abandoned session is detectable', () async {
      // Seed vocabulary first
      final category = await vocabulary.createCategory('Numbers');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'one',
          meaning: 'หนึ่ง',
          partOfSpeech: 'number',
        ),
      );

      final session = await learning.startQuiz();
      expect(session.questions, isNotEmpty);

      // Simulate app close mid-session
      final active = await learning.getActiveSession();
      expect(active, isNotNull);
      expect(active!.id, session.id);
      expect(active.state, 'active');

      // Abandon it (user chose not to resume)
      await learning.abandonActiveSessions();

      final stillActive = await learning.getActiveSession();
      expect(stillActive, isNull);
    });

    test('S3: Learning history is queryable after completion', () async {
      // Seed vocabulary first so quiz has questions
      final category = await vocabulary.createCategory('Travel');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'ticket',
          meaning: 'ตั๋ว',
          partOfSpeech: 'noun',
        ),
      );

      final session = await learning.startQuiz();
      expect(session.questions, isNotEmpty);
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: session.questions.first.word.id,
        promptMode: 'quiz',
        isCorrect: true,
        responseTimeMs: 1500,
        attemptNumber: 1,
      );
      await learning.finishSession(session.id);

      final history = await learning.listSessionHistory(limit: 10);
      expect(history, isNotEmpty);
      expect(history.first.state, 'completed');
      expect(history.first.correctCount, greaterThan(0));
    });

    test('S4: Guest-to-registered upgrade preserves data', () async {
      final guest = await owners.getOrCreateActiveOwner();

      final category = await vocabulary.createCategory('Food');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'apple',
          meaning: 'แอปเปิ้ล',
          partOfSpeech: 'noun',
        ),
      );

      // Upgrade guest to registered
      final result = await upgrade.call(
        activeOwnerId: guest.id,
        firebaseUid: 'firebase-test-uid',
      );

      // Verify upgrade completed (mode should be anonymousBound or mergedExisting)
      expect(result.mode, isNot(equals('alreadyBound')));

      // Verify vocabulary still accessible under active owner
      final words = await vocabulary.getGameWords(limit: 10);
      expect(words.length, greaterThanOrEqualTo(1));
    });

    test('S5: Reward balance is zero initially and increases with quiz', () async {
      await owners.getOrCreateActiveOwner();
      final account = await rewards.load();
      expect(account.balance, 0);

      // Seed vocabulary for quiz
      final category = await vocabulary.createCategory('Animals');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'cat',
          meaning: 'แมว',
          partOfSpeech: 'noun',
        ),
      );

      // Record a correct answer which grants XP
      final session = await learning.startQuiz();
      expect(session.questions, isNotEmpty);
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: session.questions.first.word.id,
        promptMode: 'quiz',
        isCorrect: true,
        responseTimeMs: 1000,
        attemptNumber: 1,
      );
      await learning.finishSession(session.id);

      // After answering, balance should be > 0 (XP granted per correct answer)
      final updatedAccount = await rewards.load();
      expect(updatedAccount.balance, greaterThan(0));
    });

    test('S6: Data deletion erases all owner-scoped records', () async {
      final owner = await owners.getOrCreateActiveOwner();
      final category = await vocabulary.createCategory('Test');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'hello',
          meaning: 'สวัสดี',
          partOfSpeech: 'greeting',
        ),
      );
      final session = await learning.startQuiz();
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: session.questions.first.word.id,
        promptMode: 'quiz',
        isCorrect: true,
        responseTimeMs: 500,
        attemptNumber: 1,
      );

      // Delete all data
      final deletion = LocalDataDeletion(database);
      final deleted = await deletion.eraseAll(
        ownerId: owner.id,
        deleteVocabulary: true,
      );
      expect(deleted, greaterThan(0));

      // Verify learning history is empty
      final history = await learning.listSessionHistory(limit: 10);
      expect(history, isEmpty);
    });
  });
}
