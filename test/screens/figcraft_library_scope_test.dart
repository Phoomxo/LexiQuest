import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

void main() {
  testWidgets(
    'library hides A immediately while the replacement B stream waits',
    (tester) async {
      final held = StreamController<List<VocabularyCategorySummary>>();
      final caseA = _useCases(_Repository(_category('A')), _Owners('A'));
      final caseB = _useCases(
        _Repository(_category('B'), libraryGate: held),
        _Owners('B'),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: CategoriesPage(vocabulary: caseA)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ชุด A'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(home: CategoriesPage(vocabulary: caseB)),
        );
        await tester.pump();
        expect(find.text('ชุด A'), findsNothing);
        expect(find.text('ชุด B'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(held.close);
      }
    },
  );

  testWidgets(
    'word list hides A immediately while the replacement B stream waits',
    (tester) async {
      final held = StreamController<List<VocabularyWord>>();
      final caseA = _useCases(
        _Repository(_category('A'), words: [_word('A')]),
        _Owners('A'),
      );
      final caseB = _useCases(
        _Repository(_category('B'), wordsGate: held),
        _Owners('B'),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: VocabListScreen(
              categoryId: 'A',
              categoryName: 'ชุด A',
              vocabulary: caseA,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('secret-A'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            home: VocabListScreen(
              categoryId: 'B',
              categoryName: 'ชุด B',
              vocabulary: caseB,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('secret-A'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(held.close);
      }
    },
  );

  testWidgets('global add ignores a second callback in the same frame', (
    tester,
  ) async {
    final held = StreamController<List<VocabularyCategory>>.broadcast();
    final repository = _Repository(_category('A'), categoriesGate: held);
    final cases = _useCases(repository, _Owners('A'));
    try {
      await tester.pumpWidget(
        MaterialApp(home: CategoriesPage(vocabulary: cases)),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<TextButton>(find.byKey(const ValueKey('library-add-word')))
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      await tester.pump();
      expect(repository.categoryReads, 1);
      held.add([repository.category]);
      await _pumpUntil(tester, find.text('เลือกชุดที่จะเพิ่มคำ'));
      await tester.pumpAndSettle();
      expect(find.text('เลือกชุดที่จะเพิ่มคำ'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(held.close);
    }
  });

  testWidgets(
    'destination read cannot open an old use case after scope replacement',
    (tester) async {
      final held = StreamController<List<VocabularyCategory>>();
      final repositoryA = _Repository(_category('A'), categoriesGate: held);
      final caseA = _useCases(repositoryA, _Owners('A'));
      final caseB = _useCases(_Repository(_category('B')), _Owners('B'));
      try {
        await tester.pumpWidget(
          MaterialApp(home: CategoriesPage(vocabulary: caseA)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('library-add-word')));
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(home: CategoriesPage(vocabulary: caseB)),
        );
        await tester.pumpAndSettle();
        held.add([repositoryA.category]);
        await tester.pumpAndSettle();
        expect(find.text('เลือกชุดที่จะเพิ่มคำ'), findsNothing);
        expect(find.byType(VocabListScreen), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(held.close);
      }
    },
  );

  testWidgets(
    'destination chosen after an owner change does not open the old set',
    (tester) async {
      final owners = _Owners('A');
      final cases = _useCases(_Repository(_category('A')), owners);
      await tester.pumpWidget(
        MaterialApp(home: CategoriesPage(vocabulary: cases)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-add-word')));
      await _pumpUntil(tester, find.text('เลือกชุดที่จะเพิ่มคำ'));
      await tester.pumpAndSettle();
      expect(find.text('เลือกชุดที่จะเพิ่มคำ'), findsOneWidget);
      owners.id = 'B';
      await tester.tap(find.text('ชุด A').last);
      await tester.pumpAndSettle();
      expect(find.byType(VocabListScreen), findsNothing);
      expect(find.text('พิมพ์คำศัพท์'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'nested destination creation keeps the owner from the open sheet',
    (tester) async {
      final owners = _Owners('A');
      final repository = _Repository(_category('A'));
      final cases = _useCases(repository, owners);
      await tester.pumpWidget(
        MaterialApp(home: CategoriesPage(vocabulary: cases)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-add-word')));
      await _pumpUntil(tester, find.text('เลือกชุดที่จะเพิ่มคำ'));
      await tester.pumpAndSettle();
      owners.id = 'B';
      await tester.tap(find.text('สร้างชุดคำศัพท์ใหม่'));
      final nameField = find.byKey(const ValueKey('category-name-field'));
      await _pumpUntil(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget.key == const ValueKey('category-name-field') ||
              (widget is Text &&
                  widget.data == 'บัญชีเปลี่ยนแล้ว กรุณาเลือกชุดใหม่'),
        ),
      );
      await tester.pumpAndSettle();
      if (nameField.evaluate().isNotEmpty) {
        await tester.enterText(nameField, 'ชุดสังเคราะห์ที่ต้องไม่เขียน');
        await tester.tap(find.byKey(const ValueKey('save-category')));
        await tester.pumpAndSettle();
      }
      expect(repository.createCategoryCalls, 0);
      expect(repository.createdCategories, isEmpty);
      expect(find.byType(VocabListScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 50; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

VocabularyUseCases _useCases(_Repository repository, _Owners owners) =>
    VocabularyUseCases(
      owners: owners,
      vocabulary: repository,
      generateId: () => 'unused',
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );

VocabularyCategory _category(String id) => VocabularyCategory(
  id: id,
  ownerId: id,
  name: 'ชุด $id',
  normalizedName: 'ชุด ${id.toLowerCase()}',
  sortOrder: 0,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 11, 14),
  updatedAtUtc: DateTime.utc(2026, 11, 14),
);

VocabularyWord _word(String id) => VocabularyWord(
  id: 'word-$id',
  ownerId: id,
  categoryId: id,
  spelling: 'secret-$id',
  normalizedSpelling: 'secret-${id.toLowerCase()}',
  meaning: 'คำของ $id',
  normalizedMeaning: 'คำของ ${id.toLowerCase()}',
  partOfSpeech: 'noun',
  source: 'synthetic',
  isGlobal: false,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 11, 14),
  updatedAtUtc: DateTime.utc(2026, 11, 14),
);

final class _Owners extends Fake implements LocalOwnerRepository {
  _Owners(this.id);
  String id;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 11, 14));
}

final class _Repository extends Fake implements VocabularyRepository {
  _Repository(
    this.category, {
    this.words = const [],
    this.libraryGate,
    this.wordsGate,
    this.categoriesGate,
  });
  final VocabularyCategory category;
  final List<VocabularyWord> words;
  final StreamController<List<VocabularyCategorySummary>>? libraryGate;
  final StreamController<List<VocabularyWord>>? wordsGate;
  final StreamController<List<VocabularyCategory>>? categoriesGate;
  var categoryReads = 0;
  var createCategoryCalls = 0;
  final createdCategories = <VocabularyCategory>[];
  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory value) async {
    createCategoryCalls++;
    createdCategories.add(value);
    return value;
  }

  @override
  Stream<List<VocabularyCategorySummary>> watchLibrary(String ownerId) =>
      libraryGate?.stream ??
      Stream.value([
        VocabularyCategorySummary(
          category: category,
          wordCount: words.length,
          previewSpellings: words.map((word) => word.spelling).take(3).toList(),
        ),
      ]);
  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      wordsGate?.stream ?? Stream.value(words);
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    categoryReads++;
    return categoriesGate?.stream ?? Stream.value([category]);
  }
}
