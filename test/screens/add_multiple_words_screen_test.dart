import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_import_file_parser.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_import_file_picker.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';

void main() {
  late AppDatabase database;
  late VocabularyUseCases vocabulary;
  late ImportVocabulary importer;
  late String categoryId;
  var id = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'vocab-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    importer = ImportVocabulary(
      owners: owners,
      repository: DriftVocabularyImportRepository(database),
      generateId: () => 'import-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    categoryId = (await vocabulary.createCategory('Travel')).id;
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: categoryId,
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required VocabularyImportFilePicker pickFile,
    double textScale = 1,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey('open-import'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AddMultipleWordsScreen(
                    categoryId: categoryId,
                    categoryName: 'Travel',
                    importer: importer,
                    vocabulary: vocabulary,
                    filePicker: pickFile,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  VocabularyImportFile file(
    Uint8List bytes, {
    required String name,
    String? mimeType,
  }) => VocabularyImportFile(name: name, mimeType: mimeType, bytes: bytes);

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var index = 0; index < 50; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList(growable: false);
    fail(
      'Widget did not appear after bounded pumps: $finder. '
      'Visible text: $visibleText',
    );
  }

  testWidgets('preview stays read-only until edit and confirm', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = Uint8List.fromList(
      utf8.encode(
        'word,meaning,partOfSpeech\n'
        'station,สถานี,noun\n'
        'travel,,verb\n'
        'train,รถไฟ,noun',
      ),
    );
    await pumpScreen(
      tester,
      textScale: 2,
      pickFile: () async =>
          file(bytes, name: 'travel.csv', mimeType: 'text/csv'),
    );
    await tester.tap(find.byKey(const ValueKey('open-import')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await pumpUntilFound(tester, find.text('ผ่าน 1 · ต้องแก้ 1 · ซ้ำ 1'));

    expect(find.text('ผ่าน 1 · ต้องแก้ 1 · ซ้ำ 1'), findsOneWidget);
    expect(await database.select(database.vocabularyImports).get(), isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('confirm-import')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirm-import')))
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('edit-import-row-2')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('edit-import-row-2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('edit-import-word')), '');
    await tester.enterText(
      find.byKey(const ValueKey('edit-import-part-of-speech')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('save-import-row')));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('edit-import-word')),
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.errorText,
      'กรอกคำศัพท์',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('edit-import-meaning')),
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.errorText,
      'กรอกความหมาย',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('edit-import-part-of-speech')),
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.errorText,
      'กรอกชนิดของคำ',
    );

    await tester.enterText(
      find.byKey(const ValueKey('edit-import-word')),
      'travel',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-import-meaning')),
      'เดินทาง',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-import-part-of-speech')),
      'verb',
    );
    await tester.tap(find.byKey(const ValueKey('save-import-row')));
    await tester.pumpAndSettle();

    expect(find.text('ผ่าน 2 · ต้องแก้ 0 · ซ้ำ 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-import')));
    await pumpUntilFound(tester, find.byKey(const ValueKey('open-import')));

    final imports = await database.select(database.vocabularyImports).get();
    expect(imports, hasLength(1));
    expect(imports.single.acceptedCount, 2);
    expect(imports.single.duplicateCount, 1);
    expect(imports.single.rejectedCount, 0);
    final words = await tester.runAsync(
      () => vocabulary.watchWords(categoryId).first,
    );
    expect(words, hasLength(3));
  });

  testWidgets('picker and preview cancellation never persist', (tester) async {
    var pickCount = 0;
    await pumpScreen(
      tester,
      pickFile: () async {
        pickCount++;
        if (pickCount > 1) return null;
        return file(
          Uint8List.fromList(utf8.encode('travel,เดินทาง,verb')),
          name: 'travel.csv',
          mimeType: 'text/csv',
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await pumpUntilFound(tester, find.byKey(const ValueKey('confirm-import')));
    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confirm-import')), findsOneWidget);
    expect(await database.select(database.vocabularyImports).get(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('cancel-import-preview')));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('choose-import-file')),
    );

    expect(find.byKey(const ValueKey('confirm-import')), findsNothing);
    expect(await database.select(database.vocabularyImports).get(), isEmpty);
  });

  testWidgets('pending replacement labels the import operation', (
    tester,
  ) async {
    final pending = Completer<VocabularyImportFile?>();
    var pickCount = 0;
    await pumpScreen(
      tester,
      pickFile: () {
        pickCount++;
        if (pickCount > 1) return pending.future;
        return Future.value(
          file(
            Uint8List.fromList(utf8.encode('travel,เดินทาง,verb')),
            name: 'travel.csv',
            mimeType: 'text/csv',
          ),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await pumpUntilFound(tester, find.byKey(const ValueKey('confirm-import')));

    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังนำเข้าคำศัพท์',
    );
    pending.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('failed replacement cannot confirm a stale preview', (
    tester,
  ) async {
    var pickCount = 0;
    await pumpScreen(
      tester,
      pickFile: () async {
        pickCount++;
        if (pickCount > 1) {
          throw const VocabularyImportFileFailure('fileTooLarge');
        }
        return file(
          Uint8List.fromList(utf8.encode('travel,เดินทาง,verb')),
          name: 'travel.csv',
          mimeType: 'text/csv',
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await pumpUntilFound(tester, find.byKey(const ValueKey('confirm-import')));

    await tester.tap(find.byKey(const ValueKey('choose-import-file')));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('import-file-error')),
    );

    expect(find.byKey(const ValueKey('confirm-import')), findsNothing);
    expect(await database.select(database.vocabularyImports).get(), isEmpty);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.byKey(const ValueKey('import-file-error')),
              matching: find.byType(Semantics),
            ),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });
}
