import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_study_preferences_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/study_preferences.dart';
import 'package:vocab_learning_app/screens/study_preferences_panel.dart';

void main() {
  testWidgets('speaking and a closed goal persist; owner switch hides them', (
    tester,
  ) async {
    final db = (await tester.runAsync(() async {
      final database = AppDatabase(NativeDatabase.memory());
      await database.customStatement(
        "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-a',1,1),('owner-b',1,0)",
      );
      return database;
    }))!;
    final repo = DriftStudyPreferencesRepository(
      db,
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    Widget panel() => MaterialApp(
      home: Scaffold(
        body: StudyPreferencesPanel(
          repository: repo,
          ownerId: 'owner-a',
          loadCivilToday: () async => DateTime.utc(2026, 11, 14),
        ),
      ),
    );
    Future<void> tapText(String text) async {
      final target = find.text(text);
      await _until(tester, target);
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await tester.pump();
    }

    try {
      await tester.pumpWidget(panel());
      await tapText('ฟังเสียงแล้วลองพูดตาม');
      await tapText('บันทึกวิธีเรียน');
      await _untilCondition(
        tester,
        () async =>
            (await repo.load(ownerId: 'owner-a')).method?.name == 'speaking',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(panel());
      await _until(tester, find.text('ฟังเสียงแล้วลองพูดตาม'));
      final group = tester.widget<RadioGroup<StudyMethod>>(
        find
            .ancestor(
              of: find.text('ฟังเสียงแล้วลองพูดตาม'),
              matching: find.byType(RadioGroup<StudyMethod>),
            )
            .first,
      );
      expect(group.groupValue, StudyMethod.speaking);

      await tapText('ตั้งวันเป้าหมาย');
      await _until(tester, find.byType(DatePickerDialog));
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await _until(tester, find.text('อีก 1 วัน'));
      expect(find.text('15/11/2026'), findsOneWidget);
      await tapText('ปิดเป้าหมายนี้');
      await _until(tester, find.text('ปิดเป้าหมายแล้ว'));
      final saved = (await tester.runAsync(
        () => repo.load(ownerId: 'owner-a'),
      ))!;
      expect(saved.goalState.name, 'closed');

      await tester.runAsync(
        () => db.transaction(() async {
          await db.customUpdate(
            "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
            updates: {db.localOwners},
          );
          await db.customUpdate(
            "UPDATE local_owners SET is_active=1 WHERE id='owner-b'",
            updates: {db.localOwners},
          );
        }),
      );
      await _until(tester, find.text('บัญชีผู้เรียนเปลี่ยนแล้ว'));
      expect(find.text('ฟังเสียงแล้วลองพูดตาม'), findsNothing);
      expect(find.text('ปิดเป้าหมายแล้ว'), findsNothing);
      expect(
        await tester.runAsync(() => db.select(db.answerAttempts).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.outboxOperations).get()),
        isEmpty,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var closed = false;
      Object? closeError;
      db.close().then(
        (_) => closed = true,
        onError: (Object error) {
          closeError = error;
          closed = true;
        },
      );
      for (var i = 0; i < 100 && !closed; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(closed, isTrue);
      expect(closeError, isNull);
    }
  });

  testWidgets('panel saves choices and explicit skip without learning writes', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => (() async {
        final database = AppDatabase(NativeDatabase.memory());
        await database.customStatement(
          "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-a',1,1)",
        );
        return database;
      })().timeout(const Duration(seconds: 5)),
    ))!;
    final repo = DriftStudyPreferencesRepository(
      db,
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudyPreferencesPanel(
              repository: repo,
              ownerId: 'owner-a',
              loadCivilToday: () async => DateTime.utc(2026, 11, 14),
            ),
          ),
        ),
      );
      await _until(tester, find.text('ข้ามคำถาม'));
      await tester.ensureVisible(find.text('ข้ามคำถาม'));
      await tester.tap(find.text('ข้ามคำถาม'));
      await _untilCondition(
        tester,
        () async => (await db.select(db.learningPreferences).get()).isNotEmpty,
      );
      expect(
        (await tester.runAsync(
          () => db.select(db.learningPreferences).getSingle(),
        ))!.onboardingState,
        'skipped',
      );
      expect(
        await tester.runAsync(() => db.select(db.answerAttempts).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.outboxOperations).get()),
        isEmpty,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var closed = false;
      Object? closeError;
      db.close().then(
        (_) => closed = true,
        onError: (Object error) {
          closeError = error;
          closed = true;
        },
      );
      for (var i = 0; i < 100 && !closed; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        closed,
        isTrue,
        reason: 'database close must finish after panel unmount',
      );
      expect(closeError, isNull);
    }
  });
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Panel did not show $finder');
}

Future<void> _untilCondition(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (await tester.runAsync(condition) == true) return;
  }
  fail('Panel save did not finish');
}
