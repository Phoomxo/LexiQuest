import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_local_content_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/local_content_report.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/bookmarked_vocabulary_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/widgets/local_content_report_queue.dart';

const _search = ValueKey('category-search');
const _notSent = 'ยังไม่ส่งถึงผู้จัดทำ';
const _stationReport = 'station · สถานี';
const _passportReport = 'passport · หนังสือเดินทาง';
const _ownerB = 'synthetic-review-desk-b';
final _now = DateTime.utc(2026, 11, 15, 12);

void main() {
  testWidgets('Review Desk local report queue returns to the Library filter', (
    tester,
  ) async {
    await _withLibrary(tester, (database, _) async {
      final search = find.byKey(_search);
      await _tap(tester, 'เลือกระดับภาษา');
      await _tap(tester, 'A2');
      await _waitFor(tester, find.text('เลือกระดับภาษา · A2'));
      await _showLibrarySearch(tester);
      await tester.enterText(search, 'stat');
      FocusManager.instance.primaryFocus?.unfocus();
      await _waitFor(tester, find.text('station'));
      expect(find.text('stationery'), findsNothing);
      final before = await database.select(database.localContentReports).get();
      final outbox = await database.select(database.outboxOperations).get();

      await _openQueue(tester);
      await _waitFor(tester, _queueText(_stationReport));
      expect(_queueText('ประโยคตัวอย่างสะกดผิด'), findsOneWidget);
      expect(_queueText('Synthetic example for station.'), findsWidgets);
      expect(_queueText(_notSent), findsWidgets);
      expect(_queueText(_passportReport), findsNothing);
      await _tap(tester, 'กลับศูนย์ทบทวน');
      await _waitFor(tester, find.text('เลือกสิ่งที่จะทบทวน'));
      await _tap(tester, 'กลับคลังคำ');

      await _waitFor(tester, find.text('คลังคำศัพท์'));
      await _showLibrarySearch(tester);
      expect(tester.widget<SearchBar>(search).controller!.text, 'stat');
      await _waitFor(tester, find.text('station'));
      expect(find.text('เลือกระดับภาษา · A2'), findsOneWidget);
      expect(find.text('stationery'), findsNothing);
      expect(await database.select(database.localContentReports).get(), before);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), outbox);
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.researchConsents).get(), isEmpty);
    });
  });

  testWidgets('Review Desk report queue separates owners in the same Library', (
    tester,
  ) async {
    await _withLibrary(tester, (database, ownerA) async {
      await _openQueue(tester);
      final oldReport = _queueText(_stationReport);
      final newReport = _queueText(_passportReport);
      await _waitFor(tester, oldReport);
      expect(newReport, findsNothing);

      await _activateOwner(database, from: ownerA, to: _ownerB);
      await _waitFor(tester, oldReport, disappears: true);
      expect(newReport, findsNothing);
      final library = _currentScreen<CategoriesPage>();
      for (var back = 0; back < 2 && library.evaluate().isEmpty; back++) {
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await _waitFor(tester, find.text('เอกสารของ B'));
      await _openQueue(tester);
      await _waitFor(tester, newReport);
      expect(oldReport, findsNothing);
      expect(_queueText(_notSent), findsWidgets);
    });
  });

  testWidgets('Review Desk reports an empty queue for the active owner', (
    tester,
  ) async {
    await _withLibrary(tester, (database, ownerA) async {
      final before = await database
          .select(database.localContentReports)
          .getSingle();
      expect(before.ownerId, ownerA);
      await _activateOwner(database, from: ownerA, to: _ownerB);
      await _waitFor(tester, find.text('เอกสารของ B'));
      await _openQueue(tester);
      await _waitFor(tester, _queueText('ยังไม่มีรายงาน'));
      expect(_queueText(_stationReport), findsNothing);
      expect(_queueText(_passportReport), findsNothing);
      expect(_queueText(_notSent), findsNothing);
      await _tap(tester, 'กลับศูนย์ทบทวน');
      await _tap(tester, 'กลับคลังคำ');
      await _waitFor(tester, find.text('เอกสารของ B'));

      await _activateOwner(database, from: _ownerB, to: ownerA);
      await _waitFor(tester, find.text('การเดินทาง'));
      await _openQueue(tester);
      await _waitFor(tester, _queueText(_stationReport));
      expect(_queueText(_notSent), findsWidgets);
      expect(
        await database.select(database.localContentReports).getSingle(),
        before,
      );
    }, queueForB: false);
  });

  testWidgets('Review Desk opens the saved words across the current sets', (
    tester,
  ) async {
    await _withLibrary(tester, (database, _) async {
      final words = await database.select(database.vocabularyWords).get();
      final outbox = await database.select(database.outboxOperations).get();
      await _openDesk(tester);
      await _tap(tester, 'เก็บไว้อ่านอีกครั้ง');
      final savedWords = _currentScreen<BookmarkedVocabularyScreen>();
      Finder savedWord(String spelling) =>
          find.descendant(of: savedWords, matching: find.text(spelling));
      await _waitFor(tester, savedWords);
      await _waitFor(tester, savedWord('เก็บในเครื่อง · เปิดดูได้ขณะออฟไลน์'));
      expect(savedWord('คำที่เก็บไว้'), findsOneWidget);
      await _reveal(
        tester,
        savedWord('compass'),
        within: savedWords,
        delta: 140,
      );
      expect(savedWord('compass'), findsOneWidget);
      await _reveal(
        tester,
        savedWord('station'),
        within: savedWords,
        delta: 140,
      );
      expect(savedWord('stationery'), findsNothing);
      expect(savedWord('passport'), findsNothing);

      await _tap(tester, 'station');
      await _waitFor(tester, find.text('แก้ไขคำ'));
      expect(find.text('สถานี'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _waitFor(tester, savedWords);
      await tester.binding.handlePopRoute();
      await _waitFor(tester, find.text('เลือกสิ่งที่จะทบทวน'));
      expect(await database.select(database.vocabularyWords).get(), words);
      expect(await database.select(database.outboxOperations).get(), outbox);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    });
  });
}

Future<void> _withLibrary(
  WidgetTester tester,
  Future<void> Function(AppDatabase database, String ownerA) run, {
  bool queueForB = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic-review-desk-a',
    nowUtc: () => _now,
  );
  var nextId = 0;
  String generatedId() => 'synthetic-review-desk-${++nextId}';
  final vocabulary = VocabularyUseCases(
    owners: owners,
    vocabulary: DriftVocabularyRepository(database),
    generateId: generatedId,
    nowUtc: () => _now,
  );
  final reports = DriftLocalContentReportRepository(database);

  Future<void> addWord(
    String category,
    String spelling,
    String meaning,
    String level, {
    bool bookmarked = false,
  }) async {
    final set = await vocabulary.createCategory(category);
    final word = await vocabulary.createWord(
      CreateWordCommand(
        categoryId: set.id,
        spelling: spelling,
        meaning: meaning,
        partOfSpeech: 'noun',
        cefrLevel: level,
      ),
    );
    if (bookmarked) {
      await vocabulary.setBookmarked(
        expectedOwnerId: word.ownerId,
        wordId: word.id,
        bookmarked: true,
      );
    }
  }

  Future<void> queueReport(
    String owner,
    String spelling,
    String meaning,
    LocalContentReportReason reason,
  ) => reports.queue(
    expectedOwnerId: owner,
    report: LocalContentReportDraft(
      id: 'report-$spelling',
      sourceKind: 'localSource',
      sourceId: 'local-source:synthetic-$spelling',
      sourceRevision: 1,
      spelling: spelling,
      meaning: meaning,
      sentence: 'Synthetic example for $spelling.',
      reason: reason,
      createdAtUtc: _now,
    ),
  );

  try {
    final ownerA = (await tester.runAsync(() async {
      final owner = await owners.getOrCreateActiveOwner();
      await addWord('การเดินทาง', 'station', 'สถานี', 'A2', bookmarked: true);
      await addWord(
        'อุปกรณ์เดินทาง',
        'compass',
        'เข็มทิศ',
        'A2',
        bookmarked: true,
      );
      await addWord('ของใช้', 'stationery', 'เครื่องเขียน', 'A1');
      await queueReport(
        owner.id,
        'station',
        'สถานี',
        LocalContentReportReason.exampleSpellingError,
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: _ownerB,
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      await _activateOwner(database, from: owner.id, to: _ownerB);
      await addWord(
        'เอกสารของ B',
        'passport',
        'หนังสือเดินทาง',
        'A2',
        bookmarked: true,
      );
      if (queueForB) {
        await queueReport(
          _ownerB,
          'passport',
          'หนังสือเดินทาง',
          LocalContentReportReason.translationMismatch,
        );
      }
      await _activateOwner(database, from: _ownerB, to: owner.id);
      return owner.id;
    }))!;
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _GuestSession(),
          database: database,
          localOwners: owners,
          localContentReports: reports,
          vocabulary: vocabulary,
          learning: LearningUseCases(
            owners: owners,
            repository: DriftLearningRepository(database),
            generateId: generatedId,
            nowUtc: () => _now,
            buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
          ),
          progress: ProgressUseCases(
            owners: owners,
            queries: DriftProgressQueries(database),
            nowUtc: () => _now,
          ),
        ),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const CategoriesPage(),
        ),
      ),
    );
    await _waitFor(tester, find.text('การเดินทาง'));
    await run(database, ownerA);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(database.close);
  }
}

Future<void> _activateOwner(
  AppDatabase database, {
  required String from,
  required String to,
}) => database.transaction(() async {
  await (database.update(database.localOwners)
        ..where((row) => row.id.equals(from)))
      .write(const LocalOwnersCompanion(isActive: Value(false)));
  await (database.update(database.localOwners)
        ..where((row) => row.id.equals(to)))
      .write(const LocalOwnersCompanion(isActive: Value(true)));
});

Future<void> _openQueue(WidgetTester tester) async {
  await _openDesk(tester);
  await _tap(tester, 'รายงานที่รอส่ง');
}

Future<void> _openDesk(WidgetTester tester) async {
  await _showLibrarySearch(tester);
  await _reveal(
    tester,
    find.text('ทบทวนคำศัพท์'),
    within: _currentScreen<CategoriesPage>(),
    delta: 140,
  );
  await _tap(tester, 'ทบทวนคำศัพท์');
  await _waitFor(tester, find.text('เลือกสิ่งที่จะทบทวน'));
}

Finder _currentScreen<T extends Widget>() => find.byElementPredicate(
  (element) => element.widget is T && ModalRoute.isCurrentOf(element) == true,
  description: '$T on the current route',
);

Finder _queueText(String label) => find.descendant(
  of: _currentScreen<LocalContentReportQueue>(),
  matching: find.text(label),
);

Future<void> _showLibrarySearch(WidgetTester tester) => _reveal(
  tester,
  find.byKey(_search),
  within: _currentScreen<CategoriesPage>(),
  delta: -140,
);

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  required Finder within,
  required double delta,
}) async {
  await _waitFor(tester, within);
  final scrollable = find.descendant(
    of: within,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  final viewport = scrollable.hitTestable();
  await _waitFor(tester, viewport);
  try {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: viewport.first,
      maxScrolls: 12,
    );
  } on StateError {
    fail('Could not reveal $target. Visible text: ${_visibleText()}');
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await _waitFor(tester, button);
  await tester.ensureVisible(button.first);
  final tappable = button.hitTestable();
  await _waitFor(tester, tappable);
  await tester.tap(tappable.first);
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder target, {
  bool disappears = false,
}) async {
  for (var frame = 0; frame < 80; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isEmpty == disappears) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail(
    'Timed out waiting for $target to ${disappears ? 'disappear' : 'appear'}. '
    'Visible text: ${_visibleText()}',
  );
}

String _visibleText() => find
    .byType(Text)
    .evaluate()
    .map((element) => element.widget as Text)
    .map((text) => text.data ?? text.textSpan?.toPlainText())
    .whereType<String>()
    .take(24)
    .join(' | ');

final class _GuestSession extends Fake implements GuestSessionService {}
