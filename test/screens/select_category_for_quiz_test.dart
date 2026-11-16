import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/screens/select_category_for_quiz.dart';

void main() {
  testWidgets('empty state returns to vocabulary entry flow', (tester) async {
    final vocabulary = VocabularyUseCases(
      owners: _Owners(),
      vocabulary: _EmptyVocabularyRepository(),
      generateId: () => 'unused',
      nowUtc: () => DateTime.utc(2026, 10, 25),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SelectCategoryForQuiz(vocabulary: vocabulary),
                ),
              ),
              child: const Text('เปิดเลือกหมวด'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('เปิดเลือกหมวด'));
    await tester.pumpAndSettle();
    expect(find.text('กลับไปหน้าเรียน'), findsOneWidget);

    await tester.tap(find.text('กลับไปหน้าเรียน'));
    await tester.pumpAndSettle();
    expect(find.text('เปิดเลือกหมวด'), findsOneWidget);
  });

  testWidgets(
    'announces category loading and failure then retries with a fresh stream',
    (tester) async {
      final repository = _RetryVocabularyRepository();
      addTearDown(repository.dispose);
      final vocabulary = VocabularyUseCases(
        owners: _Owners(),
        vocabulary: repository,
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 10, 24),
      );

      await tester.pumpWidget(
        MaterialApp(home: SelectCategoryForQuiz(vocabulary: vocabulary)),
      );
      await tester.pump();

      expect(repository.watchCalls, 1);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'กำลังโหลดหมวดหมู่',
      );

      repository.firstAttempt.addError(
        StateError('synthetic category read failure'),
      );
      await tester.pumpAndSettle();

      const failureText = 'อ่านหมวดหมู่ไม่สำเร็จ กรุณาลองใหม่';
      expect(find.text(failureText), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(failureText),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsAtLeastNWidgets(1),
      );

      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();

      expect(repository.watchCalls, 2);
      expect(find.text('หมวดที่กู้คืนแล้ว'), findsOneWidget);
      expect(find.text(failureText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _EmptyVocabularyRepository extends Fake
    implements VocabularyRepository {
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      Stream.value(const []);
}

final class _Owners extends Fake implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'synthetic-owner',
    createdAtUtc: DateTime.utc(2026, 10, 24),
  );
}

final class _RetryVocabularyRepository extends Fake
    implements VocabularyRepository {
  final firstAttempt = StreamController<List<VocabularyCategory>>();
  var watchCalls = 0;

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    watchCalls++;
    if (watchCalls == 1) return firstAttempt.stream;
    final now = DateTime.utc(2026, 10, 24);
    return Stream.value([
      VocabularyCategory(
        id: 'recovered-category',
        ownerId: ownerId,
        name: 'หมวดที่กู้คืนแล้ว',
        normalizedName: 'หมวดที่กู้คืนแล้ว',
        sortOrder: 0,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    ]);
  }

  Future<void> dispose() => firstAttempt.close();
}
