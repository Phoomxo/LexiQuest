import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('retained library retry cannot restore A after Scope B', (
    tester,
  ) async {
    final held = StreamController<List<VocabularyCategorySummary>>.broadcast();
    final repositoryA = _Repository(_category('A'), libraryGate: held);
    final caseA = _useCases(repositoryA, _Owners('A'));
    final caseB = _useCases(_Repository(_category('B')), _Owners('B'));
    final app = MaterialApp(home: CategoriesPage(vocabulary: caseA));
    try {
      await tester.pumpWidget(_scope(_dependencies(caseA), app));
      await tester.pump();
      held.addError(StateError('synthetic library read failure'));
      await tester.pumpAndSettle();
      final retry = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'ลองใหม่'),
          )
          .onPressed!;
      await tester.pumpWidget(_scope(_dependencies(caseB), app));
      await tester.pumpAndSettle();
      expect(find.text('ชุด B'), findsOneWidget);

      retry();
      await tester.pump();
      held.add([
        VocabularyCategorySummary(
          category: _category('A'),
          wordCount: 0,
          previewSpellings: const [],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('ชุด A'), findsNothing);
      expect(find.text('ชุด B'), findsOneWidget);
      expect(repositoryA.libraryReads, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(held.close);
    }
  });

  testWidgets('retained search change cannot change Scope B query', (
    tester,
  ) async {
    final repositoryA = _Repository(_category('A'), words: [_word('A')]);
    final caseA = _useCases(repositoryA, _Owners('A'));
    final caseB = _useCases(_Repository(_category('B')), _Owners('B'));
    final app = MaterialApp(home: CategoriesPage(vocabulary: caseA));
    await tester.pumpWidget(_scope(_dependencies(caseA), app));
    await tester.pumpAndSettle();
    final change = tester
        .widget<SearchBar>(find.byKey(const ValueKey('category-search')))
        .onChanged!;
    await tester.pumpWidget(_scope(_dependencies(caseB), app));
    await tester.pumpAndSettle();

    change('secret');
    await tester.pumpAndSettle();
    expect(find.text('ชุดคำของฉัน'), findsOneWidget);
    expect(find.text('ชุด B'), findsOneWidget);
    expect(repositoryA.searchQueries, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retained search retry cannot replace Scope B results', (
    tester,
  ) async {
    final held = StreamController<List<VocabularyWord>>.broadcast();
    final repositoryA = _Repository(_category('A'), searchGate: held);
    final caseA = _useCases(repositoryA, _Owners('A'));
    final caseB = _useCases(
      _Repository(_category('B'), words: [_word('B')]),
      _Owners('B'),
    );
    final app = MaterialApp(home: CategoriesPage(vocabulary: caseA));
    try {
      await tester.pumpWidget(_scope(_dependencies(caseA), app));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('category-search')),
        'secret',
      );
      await tester.pump();
      held.addError(StateError('synthetic search failure'));
      await tester.pumpAndSettle();
      final retry = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'ลองใหม่'),
          )
          .onPressed!;
      await tester.pumpWidget(_scope(_dependencies(caseB), app));
      await tester.pumpAndSettle();
      expect(find.text('secret-B'), findsOneWidget);

      retry();
      await tester.pump();
      held.add([_word('A')]);
      await tester.pumpAndSettle();
      expect(find.text('secret-A'), findsNothing);
      expect(find.text('secret-B'), findsOneWidget);
      expect(repositoryA.searchQueries, [('A', 'secret')]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(held.close);
    }
  });

  testWidgets(
    'library stays scrollable above shell navigation at landscape 2x',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final cases = _useCases(
        _Repository(_category('A'), words: [_word('A')]),
        _Owners('A'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: CategoriesPage(vocabulary: cases),
            bottomNavigationBar: const SizedBox(
              height: 80,
              child: Text('เมนูหลัก'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final addWord = find.byKey(const ValueKey('library-add-word'));
      await tester.ensureVisible(addWord);
      await tester.pumpAndSettle();
      expect(addWord.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('root library cannot revive injected A after scope removal', (
    tester,
  ) async {
    final cases = _useCases(_Repository(_category('A')), _Owners('A'));
    final app = MaterialApp(
      key: GlobalKey(),
      home: CategoriesPage(vocabulary: cases),
    );
    await tester.pumpWidget(_scope(_dependencies(cases), app));
    await tester.pumpAndSettle();
    final library = tester.state(find.byType(CategoriesPage));
    expect(find.text('ชุด A'), findsOneWidget);
    await tester.pumpWidget(app);
    await tester.pump();
    expect(tester.state(find.byType(CategoriesPage)), same(library));
    expect(find.text('ชุด A'), findsNothing);
    expect(find.byKey(const ValueKey('library-add-word')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final change in ['owner', 'scope']) {
    testWidgets(
      'root delete confirmation rejects changed $change before writing',
      (tester) async {
        final owners = _Owners('A');
        final repository = _Repository(_category('A'));
        final cases = _useCases(repository, owners);
        final app = MaterialApp(home: CategoriesPage(vocabulary: cases));
        await tester.pumpWidget(_scope(_dependencies(cases), app));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('ตัวเลือกชุด ชุด A'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ลบชุดคำศัพท์'));
        await tester.pumpAndSettle();
        final confirm = tester
            .widget<ButtonStyleButton>(
              find
                  .ancestor(
                    of: find.text('ลบ'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is ButtonStyleButton,
                    ),
                  )
                  .first,
            )
            .onPressed!;
        if (change == 'owner') {
          owners.id = 'B';
        } else {
          await tester.pumpWidget(_scope(_dependencies(null), app));
        }
        await tester.pump();
        confirm();
        await tester.pumpAndSettle();
        expect(repository.deletedCategories, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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

  for (final missing in [false, true]) {
    final replacement = missing ? 'missing vocabulary' : 'owner B';
    testWidgets(
      'root library replaces injected A with inherited $replacement',
      (tester) async {
        final caseA = _useCases(_Repository(_category('A')), _Owners('A'));
        final caseB = _useCases(_Repository(_category('B')), _Owners('B'));
        final app = MaterialApp(home: CategoriesPage(vocabulary: caseA));
        await tester.pumpWidget(_scope(_dependencies(caseA), app));
        await tester.pumpAndSettle();
        final library = tester.state(find.byType(CategoriesPage));
        expect(find.text('ชุด A'), findsOneWidget);

        await tester.pumpWidget(
          _scope(_dependencies(missing ? null : caseB), app),
        );
        await tester.pump();
        expect(tester.state(find.byType(CategoriesPage)), same(library));
        expect(find.text('ชุด A'), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('ชุด B'), missing ? findsNothing : findsOneWidget);
        if (missing) {
          expect(find.byKey(const ValueKey('library-add-word')), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'selected set rejects inherited $replacement despite injected A',
      (tester) async {
        final caseA = _useCases(
          _Repository(_category('A'), words: [_word('A')]),
          _Owners('A'),
        );
        final repositoryB = _Repository(_category('B'), words: [_word('B')]);
        final caseB = _useCases(repositoryB, _Owners('B'));
        final app = MaterialApp(home: CategoriesPage(vocabulary: caseA));
        await tester.pumpWidget(_scope(_dependencies(caseA), app));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ชุด A'));
        await _pumpUntil(tester, find.text('secret-A'));
        await tester.pumpAndSettle();
        final selected = tester.state(find.byType(VocabListScreen));

        await tester.pumpWidget(
          _scope(_dependencies(missing ? null : caseB), app),
        );
        await tester.pump();
        expect(tester.state(find.byType(VocabListScreen)), same(selected));
        expect(find.text('secret-A'), findsNothing);
        expect(find.text('คำของ A · noun'), findsNothing);
        expect(find.text('ชุด A'), findsNothing);
        expect(find.text('secret-B'), findsNothing);
        expect(find.text('ชุด B'), findsNothing);
        expect(find.byKey(const ValueKey('add-word')), findsNothing);
        expect(find.byTooltip('ลบคำศัพท์ secret-A'), findsNothing);
        expect(repositoryB.wordReads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'open add menu rejects inherited $replacement before opening an editor',
      (tester) async {
        final caseA = _useCases(_Repository(_category('A')), _Owners('A'));
        final caseB = _useCases(_Repository(_category('B')), _Owners('B'));
        final app = MaterialApp(
          home: VocabListScreen(
            categoryId: 'A',
            categoryName: 'ชุด A',
            vocabulary: caseA,
          ),
        );
        await tester.pumpWidget(_scope(_dependencies(caseA), app));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add-word')));
        await tester.pumpAndSettle();
        final chooseManual = tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'พิมพ์คำศัพท์'))
            .onTap!;

        await tester.pumpWidget(
          _scope(_dependencies(missing ? null : caseB), app),
        );
        await tester.pump();
        chooseManual();
        await tester.pumpAndSettle();
        expect(find.byType(AddWordScreen), findsNothing);
        expect(find.text('เพิ่มคำใน ชุด A'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('open add menu cannot adopt a replacement category', (
    tester,
  ) async {
    final selectedId = ValueNotifier('A');
    final cases = _useCases(_Repository(_category('A')), _Owners('A'));
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: selectedId,
          builder: (_, id, _) => VocabListScreen(
            categoryId: id,
            categoryName: 'ชุด $id',
            vocabulary: cases,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester.state(find.byType(VocabListScreen));
    await tester.tap(find.byKey(const ValueKey('add-word')));
    await tester.pumpAndSettle();
    final chooseManual = tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'พิมพ์คำศัพท์'))
        .onTap!;
    selectedId.value = 'B';
    await tester.pump();
    expect(tester.state(find.byType(VocabListScreen)), same(selected));
    chooseManual();
    await tester.pumpAndSettle();
    expect(find.byType(AddWordScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    selectedId.dispose();
  });

  for (final change in ['owner', 'category', 'scope']) {
    testWidgets(
      'delete confirmation rejects a changed $change before writing',
      (tester) async {
        final selectedId = ValueNotifier('A');
        final owners = _Owners('A');
        final repository = _Repository(_category('A'), words: [_word('A')]);
        final cases = _useCases(repository, owners);
        final app = MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: selectedId,
            builder: (_, id, _) => VocabListScreen(
              categoryId: id,
              categoryName: 'ชุด $id',
              vocabulary: cases,
            ),
          ),
        );
        await tester.pumpWidget(_scope(_dependencies(cases), app));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('ลบคำศัพท์ secret-A'));
        await tester.pumpAndSettle();
        final confirm = tester
            .widget<ButtonStyleButton>(
              find
                  .ancestor(
                    of: find.text('ลบ'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is ButtonStyleButton,
                    ),
                  )
                  .first,
            )
            .onPressed!;
        switch (change) {
          case 'owner':
            owners.id = 'B';
          case 'category':
            selectedId.value = 'B';
          case 'scope':
            await tester.pumpWidget(_scope(_dependencies(null), app));
        }
        await tester.pump();
        confirm();
        await tester.pumpAndSettle();
        expect(repository.deletedWords, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        selectedId.dispose();
      },
    );
  }

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
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey('library-add-word')),
          )
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

Widget _scope(AppDependencies dependencies, Widget app) =>
    AppDependenciesScope(dependencies: dependencies, child: app);

AppDependencies _dependencies(VocabularyUseCases? vocabulary) =>
    AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      localOwners: vocabulary?.owners,
      vocabulary: vocabulary,
    );

final class _GuestSession extends Fake implements GuestSessionService {}

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
    this.searchGate,
  });
  final VocabularyCategory category;
  final List<VocabularyWord> words;
  final StreamController<List<VocabularyCategorySummary>>? libraryGate;
  final StreamController<List<VocabularyWord>>? wordsGate;
  final StreamController<List<VocabularyCategory>>? categoriesGate;
  final StreamController<List<VocabularyWord>>? searchGate;
  var categoryReads = 0;
  var libraryReads = 0;
  var wordReads = 0;
  final searchQueries = <(String, String)>[];
  var createCategoryCalls = 0;
  final createdCategories = <VocabularyCategory>[];
  final deletedWords = <(String, String)>[];
  final deletedCategories = <(String, String)>[];
  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory value) async {
    createCategoryCalls++;
    createdCategories.add(value);
    return value;
  }

  @override
  Stream<List<VocabularyCategorySummary>> watchLibrary(String ownerId) {
    libraryReads++;
    return libraryGate?.stream ??
        Stream.value([
          VocabularyCategorySummary(
            category: category,
            wordCount: words.length,
            previewSpellings: words
                .map((word) => word.spelling)
                .take(3)
                .toList(),
          ),
        ]);
  }

  @override
  Stream<List<VocabularyWord>> searchWords(String ownerId, String query) {
    searchQueries.add((ownerId, query));
    return searchGate?.stream ??
        Stream.value(
          words
              .where(
                (word) =>
                    word.normalizedSpelling.contains(query) ||
                    word.normalizedMeaning.contains(query),
              )
              .toList(growable: false),
        );
  }

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) {
    wordReads++;
    return wordsGate?.stream ?? Stream.value(words);
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    deletedWords.add((ownerId, wordId));
  }

  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) async {
    deletedCategories.add((ownerId, categoryId));
  }

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    categoryReads++;
    return categoriesGate?.stream ?? Stream.value([category]);
  }
}
