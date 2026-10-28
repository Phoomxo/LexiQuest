import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide AssociationRecord, AssociativeMemoryState;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  group('B3 Associative Reading Session Screen Tests', () {
    testWidgets('Renders stages and progresses through 6 stages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B2',
            targetWords: ['ephemeral', 'resilient'],
            passageText:
                'Life is filled with ephemeral moments that require a resilient spirit to appreciate.',
          ),
        ),
      );

      expect(find.text('อ่านแบบเชื่อมโยง (B2)'), findsOneWidget);
      expect(find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'), findsOneWidget);
      expect(find.textContaining('ephemeral moments'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(
        progress.semanticsLabel,
        'ความคืบหน้าการอ่านแบบเชื่อมโยง ขั้นตอน 1 จาก 6',
      );

      // Stage 1 -> Stage 2
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย'), findsOneWidget);

      // Stage 2 -> Stage 3
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 3: ทดสอบจากความจำ'), findsOneWidget);

      // Stage 3 -> Stage 4
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'), findsOneWidget);

      // Stage 4 -> Stage 5
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 5: แต่งประโยคใหม่'), findsOneWidget);

      // Stage 5 -> Stage 6
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 6: สรุปผล'), findsOneWidget);
      expect(find.text('พร้อมจบการฝึก'), findsOneWidget);
    });

    // ── Stage 3 — Active Recall ────────────────────────────────────────────

    testWidgets('Stage 3 shows one TextField per target word', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B1',
            targetWords: ['ephemeral', 'resilient'],
            passageText: 'Test passage.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Stage 3 (skip stages 1 and 2).
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();

      expect(find.text('ขั้นที่ 3: ทดสอบจากความจำ'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('คำที่ 1'), findsOneWidget);
      expect(find.text('คำที่ 2'), findsOneWidget);
    });

    // ── Stage 4 — Memory Association ──────────────────────────────────────

    testWidgets('Stage 4 saves associations via AssociativeLearningPort', (
      tester,
    ) async {
      final adapter = InMemoryAssociativeLearningAdapter();

      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            passageText: 'The banana is yellow.',
            associativeLearning: adapter,
            ownerId: 'owner-reading',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Stage 4.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await tester.pumpAndSettle();
      }
      expect(find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'), findsOneWidget);

      // Enter a cue for 'banana'.
      await tester.enterText(find.byType(TextField).first, 'yellow fruit');
      await tester.pumpAndSettle();

      // Advance to Stage 5 — triggers _saveAssociations.
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 5: แต่งประโยคใหม่'), findsOneWidget);

      // Association must be persisted in the in-memory adapter.
      final associations = await adapter.getAssociationsForWord(
        'owner-reading',
        'banana',
      );
      expect(associations, hasLength(1));
      expect(associations.first.content, 'yellow fruit');
      expect(associations.first.type, 'keyword');
    });

    testWidgets('Stage 4 stays put until the association is durable', (
      tester,
    ) async {
      final adapter = _FailOnceAssociativeLearningPort();
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            passageText: 'The banana is yellow.',
            associativeLearning: adapter,
            ownerId: 'owner-reading',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, 'yellow fruit');

      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'), findsOneWidget);
      expect(
        find.text('บันทึกตัวช่วยจำไม่สำเร็จ กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      final continueButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป'),
      );
      continueButton.onPressed!();
      continueButton.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('ขั้นที่ 5: แต่งประโยคใหม่'), findsOneWidget);
      expect(
        await adapter.getAssociationsForWord('owner-reading', 'banana'),
        hasLength(1),
      );
    });

    testWidgets('recall stores the revision shown in the reading activity', (
      tester,
    ) async {
      final setup = await _ownerScopedLearning();
      addTearDown(setup.database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'Source',
            targetWords: const ['station'],
            passageText: 'The station is ready for every learner today.',
            documentId: 'local-source:evidence-capture',
            learning: setup.learning,
            targetWordIds: const {'station': 'word-1'},
            targetWordContentRevisions: const {
              'station': 'local-vocabulary-v1:1',
            },
            ownerId: setup.ownerId,
          ),
        ),
      );
      await _pumpUntilText(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      for (var stage = 0; stage < 2; stage++) {
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, 'station');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _pumpUntilText(tester, 'ขั้นที่ 4: สร้างตัวช่วยจำ');
      final answer = await setup.database
          .select(setup.database.answerAttempts)
          .getSingle();
      final context =
          jsonDecode(answer.evidenceContextJson) as Map<String, dynamic>;
      expect(answer.evidenceClass, 'independentRecall');
      expect(context['contentRevision'], 'local-vocabulary-v1:1');
      expect(context['assignmentId'], isNull);
    });

    testWidgets('edited document keeps associations for each stable word', (
      tester,
    ) async {
      final adapter = InMemoryAssociativeLearningAdapter();

      Future<void> saveCue({
        required String word,
        required String wordId,
        required int revision,
        required String cue,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              key: ValueKey(revision),
              cefrLevel: 'Source',
              targetWords: [word],
              passageText: 'The $word is ready for every learner today.',
              documentId: 'local-source:same-document',
              documentRevision: revision,
              associativeLearning: adapter,
              targetWordIds: {word: wordId},
              ownerId: 'owner-reading',
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).first, cue);
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await tester.pumpAndSettle();
      }

      await saveCue(
        word: 'station',
        wordId: 'word-station',
        revision: 1,
        cue: 'train stop',
      );
      await saveCue(
        word: 'airport',
        wordId: 'word-airport',
        revision: 2,
        cue: 'plane stop',
      );

      expect(
        await adapter.getAssociationsForWord('owner-reading', 'station'),
        hasLength(1),
      );
      expect(
        await adapter.getAssociationsForWord('owner-reading', 'airport'),
        hasLength(1),
      );
    });

    testWidgets('owner switch blocks reading progress writes', (tester) async {
      final setup = await _ownerScopedLearning();
      addTearDown(setup.database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'Source',
            targetWords: const ['station'],
            passageText: 'The station is open for every learner today.',
            documentId: 'local-source:test-progress',
            learning: setup.learning,
            targetWordIds: const {'station': 'word-1'},
            ownerId: setup.ownerId,
          ),
        ),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'กำลังเตรียมบทอ่านแบบเชื่อมโยง',
      );
      await _pumpUntilText(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      await _switchOwner(setup.database, setup.ownerId);

      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();

      expect(find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'), findsOneWidget);
      expect(
        find.text('บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเปิดกิจกรรมใหม่'),
        findsOneWidget,
      );
      expect(
        await setup.database.select(setup.database.readingEvents).get(),
        isEmpty,
      );
    });

    testWidgets('owner switch blocks association writes', (tester) async {
      final setup = await _ownerScopedLearning();
      addTearDown(setup.database.close);
      final adapter = InMemoryAssociativeLearningAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'Source',
            targetWords: const ['station'],
            passageText: 'The station is open for every learner today.',
            documentId: 'local-source:test-association',
            learning: setup.learning,
            associativeLearning: adapter,
            targetWordIds: const {'station': 'word-1'},
            ownerId: setup.ownerId,
          ),
        ),
      );
      await _pumpUntilText(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      for (var stage = 1; stage <= 3; stage++) {
        if (stage == 3) {
          await tester.enterText(find.byType(TextField).first, 'station');
        }
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await _pumpUntilText(
          tester,
          stage == 1
              ? 'ขั้นที่ 2: อ่านโดยลดตัวช่วย'
              : stage == 2
              ? 'ขั้นที่ 3: ทดสอบจากความจำ'
              : 'ขั้นที่ 4: สร้างตัวช่วยจำ',
        );
      }
      await _switchOwner(setup.database, setup.ownerId);
      await tester.enterText(find.byType(TextField).first, 'train stop');

      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await tester.pumpAndSettle();

      expect(find.text('ขั้นที่ 4: สร้างตัวช่วยจำ'), findsOneWidget);
      expect(
        await adapter.getAssociationsForWord(setup.ownerId, 'station'),
        isEmpty,
      );
    });

    testWidgets(
      'source Reading returns its acknowledged result only after Stage 6',
      (tester) async {
        final setup = await _ownerScopedLearning();
        addTearDown(setup.database.close);
        LearningSessionResult? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push(
                    MaterialPageRoute<LearningSessionResult>(
                      builder: (_) => AssociativeReadingSessionScreen(
                        cefrLevel: 'Source',
                        targetWords: const ['station'],
                        passageText:
                            'The station is open for every learner today.',
                        documentId: 'local-source:result',
                        learning: setup.learning,
                        targetWordIds: const {'station': 'word-1'},
                        ownerId: setup.ownerId,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await _pumpUntilText(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
        for (var stage = 1; stage < 3; stage++) {
          await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).first, 'wrong');
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await _pumpUntilText(tester, 'ขั้นที่ 4: สร้างตัวช่วยจำ');
        for (var stage = 4; stage < 6; stage++) {
          await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
          await tester.pumpAndSettle();
        }

        expect(result, isNull);
        await tester.tap(find.text('บันทึกและจบการฝึก'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.summary.state, 'completed');
        expect(result!.summary.wrongCount, 1);
        expect(result!.mistakeWordIds, const ['word-1']);
      },
    );
  });
}

Future<({AppDatabase database, LearningUseCases learning, String ownerId})>
_ownerScopedLearning() async {
  final database = AppDatabase(NativeDatabase.memory());
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'owner-a',
    nowUtc: () => DateTime.utc(2026, 10, 21),
  );
  final owner = await owners.getOrCreateActiveOwner();
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-1',
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
          id: 'word-1',
          ownerId: owner.id,
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  var id = 0;
  return (
    database: database,
    learning: LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 21, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    ),
    ownerId: owner.id,
  );
}

Future<void> _switchOwner(AppDatabase database, String previousOwnerId) async {
  await (database.update(database.localOwners)
        ..where((row) => row.id.equals(previousOwnerId)))
      .write(const LocalOwnersCompanion(isActive: Value(false)));
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'local:owner-b', createdAtUtcMs: 2),
      );
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Widget did not show "$text" after bounded pumps.');
}

final class _FailOnceAssociativeLearningPort
    implements AssociativeLearningPort {
  final _delegate = InMemoryAssociativeLearningAdapter();
  var _first = true;

  @override
  Future<void> saveAssociation(AssociationRecord record) {
    if (_first) {
      _first = false;
      throw StateError('synthetic association failure');
    }
    return _delegate.saveAssociation(record);
  }

  @override
  Future<void> deleteAssociation(String associationId) =>
      _delegate.deleteAssociation(associationId);

  @override
  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  ) => _delegate.getAssociationsForWord(ownerId, wordKey);

  @override
  Future<List<AssociativeMemoryState>> getAllMemoryStates(String ownerId) =>
      _delegate.getAllMemoryStates(ownerId);

  @override
  Future<AssociativeMemoryState?> getMemoryState(
    String ownerId,
    String wordKey,
  ) => _delegate.getMemoryState(ownerId, wordKey);

  @override
  Future<void> updateMemoryState(AssociativeMemoryState state) =>
      _delegate.updateMemoryState(state);
}
