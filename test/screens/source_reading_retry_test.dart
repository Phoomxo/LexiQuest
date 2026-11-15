import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/source_reading_round.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

const _open = 'อ่านแล้วลองนึกคำ';
const _next = 'เสร็จแล้ว ไปขั้นถัดไป';
const _check = 'ตรวจคำตอบ';
const _word = QuizWord(
  id: 'word-1',
  categoryId: 'category-1',
  spelling: 'station',
  meaning: 'สถานี',
  partOfSpeech: 'noun',
);

void main() {
  late AppDatabase database;
  late _ReadingRepository repository;
  late DateTime now;

  setUp(() {
    database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repository = _ReadingRepository(DriftLearningRepository(database));
    now = DateTime.utc(2026, 11, 15, 9);
  });

  Future<LearningSession> session(WidgetTester tester) async => (await tester
      .runAsync(() => database.select(database.learningSessions).getSingle()))!;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(database.close);
  }

  Future<void> openRecall(
    WidgetTester tester, {
    bool enterFirstDraft = true,
  }) async {
    const passage = 'Meet me at the station.';
    final scope = SourceReadingScope(
      categoryId: _word.categoryId,
      documentId: 'local-source:retry',
      documentRevision: 1,
      passageDigest: sha256.convert(utf8.encode(passage)).toString(),
      words: const [_word],
    );
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'source-retry-owner',
      nowUtc: () => now,
    );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'source-retry-${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    final ownerId = (await tester.runAsync(() async {
      final owner = await owners.getOrCreateActiveOwner();
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: _word.categoryId,
              ownerId: owner.id,
              name: 'Travel',
              normalizedName: 'travel',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: _word.id,
              ownerId: owner.id,
              categoryId: _word.categoryId,
              spelling: _word.spelling,
              normalizedSpelling: _word.spelling,
              meaning: _word.meaning,
              normalizedMeaning: _word.meaning,
              partOfSpeech: _word.partOfSpeech,
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      return owner.id;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<LearningSessionResult>(
                builder: (_) => AssociativeReadingSessionScreen(
                  cefrLevel: 'Source',
                  targetWords: [_word.spelling],
                  passageText: passage,
                  documentId: scope.documentId,
                  targetWordIds: {_word.spelling: _word.id},
                  learning: learning,
                  ownerId: ownerId,
                  sourceScope: scope,
                ),
              ),
            ),
            child: const Text(_open),
          ),
        ),
      ),
    );
    await _tap(tester, _open);
    await _tap(tester, _next);
    await _waitFor(tester, 'ขั้นที่ 2: อ่านโดยลดตัวช่วย');
    await _tap(tester, _next);
    await _waitFor(tester, 'คำที่ 1');
    if (enterFirstDraft) {
      await tester.enterText(find.byType(TextField).first, 'ctation');
      await _waitFor(tester, 'บันทึกร่างแล้ว');
    }
  }

  testWidgets(
    'source recall accepts clean input after a control-character paste',
    (tester) async {
      try {
        await openRecall(tester, enterFirstDraft: false);
        final field = find.byType(TextField).first;
        await tester.enterText(field, 'cta\u000Btion');
        final pasted = tester.widget<TextField>(field).controller!.text;

        await tester.enterText(field, 'ctation');
        await _waitFor(tester, 'บันทึกร่างแล้ว');
        await _tap(tester, _check);
        await _waitFor(tester, 'คำตอบครั้งแรก: ctation');
        expect(find.text('คำในบทอ่าน: station'), findsOneWidget);
        expect(pasted, isNot(contains('\u000B')));
        final saved = await session(tester);
        final round = decodeSourceReadingRound(
          saved.continuationJson!,
          sessionId: saved.id,
        );
        expect(round.draft.phase, SourceReadingPhase.comparison);
        expect(round.draft.first?.answers, ['ctation']);
      } finally {
        await dispose(tester);
      }
    },
  );

  testWidgets(
    'source recall retries a lost acknowledgement with the first check',
    (tester) async {
      repository.loseFirstCheck = true;
      try {
        await openRecall(tester);
        final firstCheck = now;
        await _tap(tester, _check);
        await _waitFor(tester, 'บันทึกรอบฝึกไม่สำเร็จ กรุณาลองอีกครั้ง');
        final committed = await session(tester);
        final stored = decodeSourceReadingRound(
          committed.continuationJson!,
          sessionId: committed.id,
        );
        expect(stored.draft.phase, SourceReadingPhase.comparison);
        expect(stored.draft.first?.answers, ['ctation']);
        expect(stored.draft.first?.checkedAtUtc, firstCheck);

        now = now.add(const Duration(minutes: 2));
        await _tap(tester, _check);
        await _waitFor(tester, 'คำตอบครั้งแรก: ctation');
        expect(find.text('คำในบทอ่าน: station'), findsOneWidget);
        expect(await session(tester), committed);

        final field = find.byType(TextField).first;
        await _tap(tester, 'แก้คำตอบ');
        await _waitFor(tester, 'คำที่ 1');
        await tester.enterText(field, 'station');
        await _tap(tester, 'ตรวจอีกครั้ง');
        await _tap(tester, 'ลองใช้ในประโยค');
        await _waitFor(tester, 'ขั้นที่ 5: แต่งประโยคใหม่');
        await tester.enterText(field, 'The station opens early.');
        await _tap(tester, _next);
        await _waitFor(tester, 'จำได้ถูกต้อง: 0 / 1 คำ');
        await _tap(tester, 'บันทึกและจบการฝึก');
        await _waitFor(tester, _open);

        final attempt = (await tester.runAsync(
          () => database.select(database.answerAttempts).getSingle(),
        ))!;
        final completed = await session(tester);
        expect(attempt.sessionId, committed.id);
        expect(attempt.wordId, _word.id);
        expect(attempt.isCorrect, isFalse);
        expect(attempt.occurredAtUtcMs, firstCheck.millisecondsSinceEpoch);
        expect(completed.id, committed.id);
        expect(completed.state, 'completed');
        expect(completed.score, 0);
      } finally {
        await dispose(tester);
      }
    },
  );

  testWidgets('source recall saves the latest correction on Back', (
    tester,
  ) async {
    final release = Completer<void>();
    try {
      await openRecall(tester);
      await _tap(tester, _check);
      await _tap(tester, 'แก้คำตอบ');
      await _waitFor(tester, 'ตรวจอีกครั้ง');
      final original = await session(tester);
      repository.holdCorrection = release.future;

      final field = find.byType(TextField).first;
      await tester.enterText(field, 'st');
      await _until(
        tester,
        () => repository.correctionStarted,
        'first correction autosave to reach the repository',
      );
      await tester.enterText(field, 'stat');
      final back = tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      release.complete();
      await back;
      await _until(
        tester,
        () => repository.correctionCommitted,
        'first correction autosave to reach Drift',
      );
      await _waitFor(tester, _open);
      await tester.pumpAndSettle();

      final saved = await session(tester);
      expect(saved.id, original.id);
      expect(saved.state, 'active');
      final restored = decodeSourceReadingRound(
        saved.continuationJson!,
        sessionId: saved.id,
      );
      expect(restored.draft.phase, SourceReadingPhase.correction);
      expect(restored.draft.recall, ['stat']);
      expect(restored.draft.first?.answers, ['ctation']);
    } finally {
      if (!release.isCompleted) release.complete();
      await dispose(tester);
    }
  });
}

Future<void> _tap(WidgetTester tester, String label) async {
  await _waitFor(tester, label);
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, String text) =>
    _until(tester, () => find.text(text).evaluate().isNotEmpty, text);

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for $description');
}

final class _ReadingRepository extends Fake
    implements DurableSourceReadingRepository {
  _ReadingRepository(this.delegate);

  final DriftLearningRepository delegate;
  bool loseFirstCheck = false;
  Future<void>? holdCorrection;
  bool correctionStarted = false;
  bool correctionCommitted = false;

  @override
  Future<SourceReadingRound> openSourceReadingRound({
    required LearningSessionDraft session,
    required SourceReadingScope scope,
  }) => delegate.openSourceReadingRound(session: session, scope: scope);

  @override
  Future<SourceReadingRound> saveSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required SourceReadingDraft draft,
  }) async {
    final held =
        expected.draft.phase == SourceReadingPhase.correction &&
            draft.phase == SourceReadingPhase.correction
        ? holdCorrection
        : null;
    if (held != null) {
      holdCorrection = null;
      correctionStarted = true;
      await held;
    }
    final saved = await delegate.saveSourceReadingRound(
      ownerId: ownerId,
      expected: expected,
      draft: draft,
    );
    if (held != null) correctionCommitted = true;
    if (loseFirstCheck &&
        expected.draft.phase == SourceReadingPhase.recall &&
        draft.phase == SourceReadingPhase.comparison) {
      loseFirstCheck = false;
      throw StateError('Synthetic lost acknowledgement after first check');
    }
    return saved;
  }

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);

  @override
  Future<LearningSessionSummary> finishSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required DateTime endedAtUtc,
  }) => delegate.finishSourceReadingRound(
    ownerId: ownerId,
    expected: expected,
    endedAtUtc: endedAtUtc,
  );
}
