import 'dart:convert';
import 'dart:io';

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
import 'package:vocab_learning_app/features/learning/domain/source_reading_round.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  testWidgets(
    'source recall restores an unfinished correction after reopening',
    (tester) async {
      const passage = 'Meet me at the station.';
      const entry = 'อ่านแล้วลองนึกคำ';
      const next = 'เสร็จแล้ว ไปขั้นถัดไป';
      const word = QuizWord(
        id: 'word-1',
        categoryId: 'category-1',
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
        localRevision: 1,
      );
      final scope = SourceReadingScope(
        categoryId: word.categoryId,
        documentId: 'local-source:typed-recall',
        documentRevision: 1,
        passageDigest: sha256.convert(utf8.encode(passage)).toString(),
        words: const [word],
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lexiquest-source-reading-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/source-reading.sqlite');
      AppDatabase? database;
      var nextId = 0;

      Future<void> tap(String label) async {
        final target = find.text(label);
        await _waitFor(tester, target);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump();
      }

      Future<void> closeApp() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (database case final active?) {
          database = null;
          await tester.runAsync(active.close);
        }
      }

      Future<void> openApp({required bool seed}) async {
        final local = AppDatabase(
          DatabaseConnection(
            NativeDatabase(file),
            closeStreamsSynchronously: true,
          ),
        );
        database = local;
        final owners = DriftLocalOwnerRepository(
          local,
          generateId: () => 'synthetic-source-reader',
          nowUtc: () => DateTime.now().toUtc(),
        );
        final ownerId = (await tester.runAsync(() async {
          final owner = await owners.getOrCreateActiveOwner();
          if (seed) {
            await local
                .into(local.vocabularyCategories)
                .insert(
                  VocabularyCategoriesCompanion.insert(
                    id: word.categoryId,
                    ownerId: owner.id,
                    name: 'Travel',
                    normalizedName: 'travel',
                    createdAtUtcMs: 1,
                    updatedAtUtcMs: 1,
                  ),
                );
            await local
                .into(local.vocabularyWords)
                .insert(
                  VocabularyWordsCompanion.insert(
                    id: word.id,
                    ownerId: owner.id,
                    categoryId: word.categoryId,
                    spelling: word.spelling,
                    normalizedSpelling: word.spelling,
                    meaning: word.meaning,
                    normalizedMeaning: word.meaning,
                    partOfSpeech: word.partOfSpeech,
                    createdAtUtcMs: 1,
                    updatedAtUtcMs: 1,
                  ),
                );
          }
          return owner.id;
        }))!;
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(local),
          generateId: () => 'source-resume-${++nextId}',
          nowUtc: () => DateTime.now().toUtc(),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<LearningSessionResult>(
                    builder: (_) => AssociativeReadingSessionScreen(
                      cefrLevel: 'Source',
                      targetWords: [word.spelling],
                      passageText: passage,
                      documentId: scope.documentId,
                      targetWordIds: {word.spelling: word.id},
                      learning: learning,
                      ownerId: ownerId,
                      sourceScope: scope,
                    ),
                  ),
                ),
                child: const Text(entry),
              ),
            ),
          ),
        );
        await tap(entry);
      }

      try {
        await openApp(seed: true);
        await tap(next);
        await tap(next);
        final draft = find.byType(TextField).first;
        await _waitFor(tester, draft);
        await tester.enterText(draft, 'ctation');
        await tap('ตรวจคำตอบ');
        await _waitFor(tester, find.text('แก้คำตอบ'));
        expect(find.textContaining('ctation'), findsWidgets);
        expect(find.textContaining('station'), findsWidgets);
        await tap('แก้คำตอบ');
        await _waitFor(tester, draft);
        await tester.enterText(draft, 'stat');
        await _waitFor(tester, find.text('บันทึกร่างแล้ว'));
        final original = (await tester.runAsync(
          () => database!.select(database!.learningSessions).getSingle(),
        ))!;
        expect(jsonEncode(original.toJson()), isNot(contains(passage)));
        await closeApp();

        await openApp(seed: false);
        await _waitFor(tester, find.text('ตรวจอีกครั้ง'));
        expect(tester.widget<TextField>(draft).controller!.text, 'stat');
        await tester.enterText(draft, 'station');
        await tap('ตรวจอีกครั้ง');
        await tap('ลองใช้ในประโยค');

        await _waitFor(tester, find.text('ขั้นที่ 5: แต่งประโยคใหม่'));
        await tester.enterText(
          find.byType(TextField).first,
          'The station is near.',
        );
        await tap(next);
        await _waitFor(tester, find.text('จำได้ถูกต้อง: 0 / 1 คำ'));
        await tap('บันทึกและจบการฝึก');
        await _waitFor(tester, find.text(entry));

        final local = database!;
        final persisted = (await tester.runAsync(() async {
          return (
            await local.select(local.answerAttempts).getSingle(),
            await local.select(local.learningSessions).getSingle(),
          );
        }))!;
        final (attempt, session) = persisted;
        expect(attempt.sessionId, original.id);
        expect(attempt.ownerId, original.ownerId);
        expect(attempt.wordId, word.id);
        expect(attempt.promptMode, 'associativeRecall');
        expect(attempt.isCorrect, isFalse);
        expect(session.id, original.id);
        expect(session.state, 'completed');
        expect(session.correctCount, 0);
        expect(session.wrongCount, 1);
        expect(session.score, 0);
        expect(jsonEncode(session.toJson()), isNot(contains(passage)));
      } finally {
        await closeApp();
      }
    },
  );
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for $target');
}
