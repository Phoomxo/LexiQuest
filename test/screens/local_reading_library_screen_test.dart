import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/local_reading_library_screen.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/services/local_reading_catalog.dart';

void main() {
  testWidgets('reading back returns to library and another level can open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LocalReadingLibraryScreen(onVocabularyPractice: () {})),
    );
    await tester.tap(find.text('A1 · A book for May'));
    await tester.pumpAndSettle();
    expect(find.byType(CefrArticleReaderScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('ชุดบทอ่านเริ่มต้น'), findsOneWidget);
    final next = find.text('A2 · A change of plan');
    await tester.scrollUntilVisible(next, 200);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CefrArticleReaderScreen>(find.byType(CefrArticleReaderScreen))
          .cefrLevel,
      'A2',
    );
  });
  testWidgets('all six revised readings remain reachable on a narrow display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final level in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']) {
      final lesson = LocalReadingCatalog.forLevel(level);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(level),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: LocalReadingLibraryScreen(onVocabularyPractice: () {}),
        ),
      );
      final entry = find.text('$level · ${lesson.title}');
      await tester.scrollUntilVisible(entry, 200);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final reader = tester.widget<CefrArticleReaderScreen>(
        find.byType(CefrArticleReaderScreen),
      );
      expect(reader.content, '${lesson.text}\n\n${lesson.reflection}');
      expect(reader.contentNotice, contains('ระดับโดยประมาณ'));
      expect(reader.sessionId, isNull);
      final questionEnd = find.text(lesson.reflection.split(' ').last).last;
      await tester.ensureVisible(questionEnd);
      await tester.pumpAndSettle();
      expect(questionEnd.hitTestable(), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('cefr-reading-complete')),
      );
      await tester.pumpAndSettle();
      expect(find.text('อ่านจบแล้ว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'local reading opens without classified vocabulary or a fake session',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalReadingLibraryScreen(onVocabularyPractice: () {}),
        ),
      );
      await tester.tap(find.text('A1 · A book for May'));
      await tester.pumpAndSettle();
      final reader = tester.widget<CefrArticleReaderScreen>(
        find.byType(CefrArticleReaderScreen),
      );
      expect(reader.content, contains('May has a blue bag'));
      expect(reader.sessionId, isNull);
      expect(reader.wordId, isNull);
      expect(reader.contentNotice, contains('ยังไม่ผ่านการรับรอง'));
    },
  );

  testWidgets('existing vocabulary practice stays available', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalReadingLibraryScreen(
          onVocabularyPractice: () {
            opened = true;
          },
        ),
      ),
    );
    final action = find.text('ฝึกจากคำศัพท์ที่มีระดับ');
    await tester.scrollUntilVisible(action, 200);
    await tester.pumpAndSettle();
    await tester.tap(action);
    expect(opened, isTrue);
  });
}
