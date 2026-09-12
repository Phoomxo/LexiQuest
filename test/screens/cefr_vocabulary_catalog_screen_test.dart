import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_catalog_screen.dart';
import 'package:vocab_learning_app/screens/local_reading_library_screen.dart';
import '../features/vocabulary/expanded_cefr_catalog_test.dart'
    show loadExpandedCatalog;

void main() {
  testWidgets('catalog remains scrollable with large text and short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CefrVocabularyCatalogScreen(
          catalog: Future.value(loadExpandedCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final search = find.byKey(const ValueKey('cefr-catalog-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'about');
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('cefr-word-cefrj15:about'));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('about · A1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('main pack and C2 supplement have separate counts and search', (
    tester,
  ) async {
    final expanded = loadExpandedCatalog();
    await tester.pumpWidget(
      MaterialApp(
        home: CefrVocabularyCatalogScreen(catalog: Future.value(expanded)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('พบ 5000 จาก 5000 คำ'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ชุดเสริม C2').last);
    await tester.pumpAndSettle();
    expect(find.text('พบ 500 จาก 500 คำ'), findsOneWidget);
    final last = expanded.search(level: 'C2').last;
    await tester.enterText(
      find.byKey(const ValueKey('cefr-catalog-search')),
      last.word,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('cefr-word-${last.id}')));
    await tester.pumpAndSettle();
    expect(find.text(last.meanings.first), findsWidgets);
    expect(find.textContaining('Octanove 1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  final catalog = CefrVocabularyCatalog.fromBytes(
    File('assets/content/cefr_starter/catalog.json').readAsBytesSync(),
  );
  testWidgets(
    'offline catalog searches beyond first hundred on narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CefrVocabularyCatalogScreen(catalog: Future.value(catalog)),
        ),
      );
      await tester.pumpAndSettle();
      final last = catalog.words.last;
      await tester.enterText(
        find.byKey(const ValueKey('cefr-catalog-search')),
        last.word,
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(ValueKey('cefr-word-${last.id}'));
      await tester.scrollUntilVisible(
        entry,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text(last.meanings.first), findsWidgets);
      expect(find.textContaining('ระดับอ้างอิง'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reading library exposes the packaged vocabulary catalog route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalReadingLibraryScreen(onVocabularyPractice: () {})),
    );
    final entry = find.byKey(
      const ValueKey('reading-library-vocabulary-catalog'),
    );
    await tester.scrollUntilVisible(entry, 200);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(CefrVocabularyCatalogScreen), findsOneWidget);
  });

  testWidgets(
    'corrupt or missing catalog has a readable failure without data writes',
    (tester) async {
      final failed = Completer<CefrVocabularyCatalog>();
      await tester.pumpWidget(
        MaterialApp(home: CefrVocabularyCatalogScreen(catalog: failed.future)),
      );
      failed.completeError(
        const FormatException('synthetic integrity failure'),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังเปิดคลังคำศัพท์ไม่ได้'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
