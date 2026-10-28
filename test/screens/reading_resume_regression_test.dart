import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  for (final stage in [1, 2, 3]) {
    testWidgets(
      'reading resumes saved stage $stage before recall is committed',
      (tester) async {
        final database = db.AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'synthetic-resume-owner',
          nowUtc: () => DateTime.utc(2026),
        );
        final owner = await owners.getOrCreateActiveOwner();
        var nextId = 0;
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'synthetic-${++nextId}',
          nowUtc: () => DateTime.utc(2026),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'resume'),
        );
        await learning.saveReadingProgress(
          documentId: 'synthetic-progress',
          documentRevision: 1,
          position: stage,
          isCompleted: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'Source',
              targetWords: const ['station'],
              passageText: 'station',
              documentId: 'synthetic-progress',
              learning: learning,
              targetWordIds: const {'station': 'synthetic-word'},
              ownerId: owner.id,
            ),
          ),
        );
        final title = switch (stage) {
          1 => 'ขั้นที่ 1: อ่านพร้อมตัวช่วย',
          2 => 'ขั้นที่ 2: อ่านโดยลดตัวช่วย',
          _ => 'ขั้นที่ 3: ทดสอบจากความจำ',
        };
        await _until(tester, title);
        expect(
          find.text('เริ่มรอบใหม่โดยเก็บประวัติคำตอบเดิมไว้'),
          findsNothing,
        );
        expect(await database.select(database.answerAttempts).get(), isEmpty);
      },
    );
  }
  testWidgets(
    'unlinked reading progress starts an explained fresh recall round',
    (tester) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'synthetic-audit-owner',
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
      var id = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'synthetic-${++id}',
        nowUtc: () => DateTime.utc(2026, 10, 28),
        buildInfo: const AppBuildInfo(version: 'audit', buildId: '6500cbf3'),
      );
      Widget screen() => MaterialApp(
        home: AssociativeReadingSessionScreen(
          cefrLevel: 'Source',
          targetWords: const ['station'],
          passageText: 'We are now at the station.',
          documentId: 'local-source:synthetic-audit-reopen',
          learning: learning,
          targetWordIds: const {'station': 'synthetic-word'},
          ownerId: owner.id,
        ),
      );

      await tester.pumpWidget(screen());
      await _until(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 2: อ่านโดยลดตัวช่วย');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 3: ทดสอบจากความจำ');
      await tester.enterText(find.byType(TextField).first, 'station');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 4: สร้างตัวช่วยจำ');
      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts.single.isCorrect, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await _until(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      expect(
        find.text('เริ่มรอบใหม่โดยเก็บประวัติคำตอบเดิมไว้'),
        findsOneWidget,
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 2: อ่านโดยลดตัวช่วย');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 3: ทดสอบจากความจำ');
      await tester.enterText(find.byType(TextField).first, 'station');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 4: สร้างตัวช่วยจำ');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 5: แต่งประโยคใหม่');
      await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
      await _until(tester, 'ขั้นที่ 6: สรุปผล');
      expect(
        find.text('จำได้ถูกต้อง: 1 / 1 คำ'),
        findsOneWidget,
        reason: 'The new round must report its own answers.',
      );
      final allAttempts = await database.select(database.answerAttempts).get();
      expect(allAttempts, hasLength(2));
      expect(
        allAttempts.map((attempt) => attempt.sessionId).toSet(),
        hasLength(2),
      );
      await learning.saveReadingProgress(
        documentId: 'local-source:synthetic-audit-reopen',
        documentRevision: 1,
        position: 6,
        isCompleted: true,
        expectedOwnerId: owner.id,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await _until(tester, 'ขั้นที่ 1: อ่านพร้อมตัวช่วย');
      expect(
        find.text('เริ่มรอบใหม่โดยเก็บประวัติคำตอบเดิมไว้'),
        findsOneWidget,
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );
}

Future<void> _until(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Widget did not show "$text" after bounded pumps.');
}
