import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/select_category_for_quiz.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/widgets/handwriting_scratchpad.dart';

const _mode = 'กระดานฝึกเขียน';
const _category = 'ชุดการเดินทาง';
const _compare = 'เทียบกับคำเฉลย';
final _panel = find.byType(HandwritingScratchpad);

void main() {
  testWidgets(
    'drawing and self-check preserve the selected category and every SQLite table',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        final before = await tester.runAsync(f.snapshot);
        await _openWord(tester, f);
        await _draw(tester);
        f.updates.value++;
        await _wait(tester, () => _panel.evaluate().isNotEmpty);
        await _tap(tester, _compare);
        expect(find.text('ticket'), findsOneWidget);
        await _tap(tester, 'ฉันสะกดตรงกับเฉลย');
        expect(find.text('คุณประเมินว่าตรงกับเฉลย'), findsOneWidget);
        await _tap(tester, 'เลือกรูปแบบโจทย์อื่น');
        await _wait(tester, () => find.text('ticket').evaluate().isNotEmpty);
        expect(find.text(_category), findsWidgets);
        expect(find.text('platform'), findsOneWidget);
        await _tap(tester, 'ticket');
        await _wait(tester, () => _panel.evaluate().isNotEmpty);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, _compare))
              .onPressed,
          isNull,
        );
        await tester.binding.handlePopRoute();
        await _routeFrame(tester);
        expect(find.text(_category), findsWidgets);
        expect(find.text('platform'), findsOneWidget);
        expect(await tester.runAsync(f.snapshot), before);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'editing or deleting the selected word discards its existing draft',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        await _openWord(tester, f);
        await _draw(tester);
        await tester.runAsync(
          () => f.vocabulary.updateWord(
            UpdateWordCommand(
              id: f.wordId,
              categoryId: f.categoryId,
              spelling: 'pass',
              meaning: 'บัตรผ่าน',
              partOfSpeech: 'noun',
            ),
          ),
        );
        await _wait(
          tester,
          () => find.textContaining('เขียนคำว่า ตั๋ว').evaluate().isEmpty,
        );
        // Either reselect from the updated list or show the changed word with clean paper.
        if (_panel.evaluate().isEmpty) {
          await _wait(tester, () => find.text('pass').evaluate().isNotEmpty);
          await _tap(tester, 'pass');
        }
        await _wait(
          tester,
          () =>
              find.textContaining('เขียนคำว่า บัตรผ่าน').evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, _compare))
              .onPressed,
          isNull,
        );
        await _draw(tester);
        await tester.runAsync(() => f.vocabulary.deleteWord(f.wordId));
        await _wait(
          tester,
          () =>
              _panel.evaluate().isEmpty &&
              find.text('platform').evaluate().isNotEmpty,
        );
        expect(find.text('pass'), findsNothing);
        expect(find.textContaining('บัตรผ่าน'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'guest merge to an existing owner cannot carry the old visible handwriting draft',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(
          () => f.db.customStatement(
            "INSERT INTO local_owners(id,created_at_utc_ms,is_active,firebase_uid,account_state) VALUES ('target',1,0,'synthetic-handwriting-b','firebaseBound')",
          ),
        );
        await _openWord(tester, f);
        await _draw(tester);
        final oldId = (await tester.runAsync(
          f.owners.getOrCreateActiveOwner,
        ))!.id;
        await tester.runAsync(
          () =>
              DriftOwnerUpgradeRepository(
                f.db,
                nowUtc: () => DateTime.utc(2026, 11, 14),
                generateOwnerId: () => 'unused',
                generateConflictId: () => 'synthetic-conflict-${f.sequence++}',
              ).upgrade(
                activeOwnerId: oldId,
                firebaseUid: 'synthetic-handwriting-b',
              ),
        );
        final rehomed = await tester.runAsync(
          () => (f.db.select(
            f.db.vocabularyWords,
          )..where((row) => row.id.equals(f.wordId))).getSingle(),
        );
        expect(rehomed!.ownerId, 'target');
        f.updates.value++;
        await tester.pump();
        expect(
          _panel,
          findsNothing,
          reason: 'old ink must be hidden while ownership is checked',
        );
        await _wait(
          tester,
          () =>
              find.text('เปลี่ยนผู้ใช้แล้ว').evaluate().isNotEmpty ||
              find.text('เลือกวิธีฝึก').evaluate().isNotEmpty ||
              find.byType(SelectCategoryForQuiz).evaluate().isNotEmpty ||
              find.byType(ChooseModeScreen).evaluate().isNotEmpty,
        );
        expect(_panel, findsNothing);
        expect(find.textContaining('เขียนคำว่า ตั๋ว'), findsNothing);
        expect(find.text('ticket'), findsNothing);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final afterSelection in [false, true]) {
    testWidgets(
      'handwriting handles owner lookup failure ${afterSelection ? 'after category selection' : 'before category selection'}',
      (tester) async {
        final f = (await tester.runAsync(_Fixture.create))!;
        try {
          final before = await tester.runAsync(f.snapshot);
          await _menu(tester, f);
          if (afterSelection) {
            await _tap(tester, _mode);
            await _wait(
              tester,
              () => find.text(_category).evaluate().isNotEmpty,
            );
            expect(find.byType(SelectCategoryForQuiz), findsOneWidget);
          }
          f.ownerLookup.failNextLookup = true;
          await _tap(tester, afterSelection ? _category : _mode);
          final notice = find.text('ยังเปิดกระดานฝึกเขียนไม่ได้');
          await _wait(tester, () => notice.evaluate().isNotEmpty);
          expect(notice, findsOneWidget);
          expect(_panel, findsNothing);
          expect(find.text('ticket'), findsNothing);
          expect(tester.takeException(), isNull);
          expect(await tester.runAsync(f.snapshot), before);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  for (final hidden in [FieldFeature.quiz, FieldFeature.vocabulary]) {
    testWidgets('handwriting entry respects hidden ${hidden.name}', (
      tester,
    ) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        await _menu(
          tester,
          f,
          features: BuildFieldFeatureRegistry({
            FieldFeature.quiz: hidden == FieldFeature.quiz
                ? FieldFeatureState.hidden
                : FieldFeatureState.enabled,
            FieldFeature.vocabulary: hidden == FieldFeature.vocabulary
                ? FieldFeatureState.hidden
                : FieldFeatureState.enabled,
          }),
        );
        expect(find.text(_mode), findsNothing);
      } finally {
        await f.close(tester);
      }
    });
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 65; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for the handwriting journey');
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.pump();
  final target = find.text(text);
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _routeFrame(tester);
}

Future<void> _routeFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _menu(
  WidgetTester tester,
  _Fixture f, {
  FieldFeatureRegistry? features,
}) async {
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: f.dependencies,
      child: MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: features,
          loader: () async => f.home,
        ),
      ),
    ),
  );
  await _wait(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
  await tester.scrollUntilVisible(find.text('ดูแบบฝึกทั้งหมด'), 150);
  await _tap(tester, 'ดูแบบฝึกทั้งหมด');
  expect(find.text('เลือกวิธีฝึก'), findsOneWidget);
}

Future<void> _openWord(WidgetTester tester, _Fixture f) async {
  await _menu(tester, f);
  await _tap(tester, _mode);
  await _wait(
    tester,
    () => find.byType(SelectCategoryForQuiz).evaluate().isNotEmpty,
  );
  expect(find.byType(SelectCategoryForQuiz), findsOneWidget);
  await _wait(tester, () => find.text(_category).evaluate().isNotEmpty);
  await _tap(tester, _category);
  await _wait(tester, () => find.text('ticket').evaluate().isNotEmpty);
  await _tap(tester, 'ticket');
  await _wait(tester, () => _panel.evaluate().isNotEmpty);
  expect(find.textContaining('เขียนคำว่า ตั๋ว'), findsOneWidget);
}

Future<void> _draw(WidgetTester tester) async {
  final board = find.bySemanticsLabel('พื้นที่ฝึกเขียน');
  await tester.ensureVisible(board);
  await tester.pump();
  await tester.drag(board, const Offset(30, 8));
  await tester.pump();
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, _compare))
        .onPressed,
    isNotNull,
  );
}

final class _Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final updates = ValueNotifier<int>(0);
  late final DriftLocalOwnerRepository owners;
  late final _OwnerLookup ownerLookup;
  late final VocabularyUseCases vocabulary;
  late final AppDependencies dependencies;
  late final ProgressSnapshot home;
  late final String categoryId, wordId;
  var sequence = 0;

  static Future<_Fixture> create() async {
    final f = _Fixture();
    final at = DateTime.utc(2026, 10, 30);
    f.owners = DriftLocalOwnerRepository(
      f.db,
      generateId: () => 'guest',
      nowUtc: () => at,
    );
    f.ownerLookup = _OwnerLookup(f.owners);
    f.vocabulary = VocabularyUseCases(
      owners: f.ownerLookup,
      vocabulary: DriftVocabularyRepository(f.db),
      generateId: () => 'synthetic-${f.sequence++}',
      nowUtc: () => at,
    );
    f.categoryId = (await f.vocabulary.createCategory(_category)).id;
    Future<String> word(String spelling, String meaning) async =>
        (await f.vocabulary.createWord(
          CreateWordCommand(
            categoryId: f.categoryId,
            spelling: spelling,
            meaning: meaning,
            partOfSpeech: 'noun',
          ),
        )).id;
    f.wordId = await word('ticket', 'ตั๋ว');
    await word('platform', 'ชานชาลา');
    f.dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _Guest(),
      database: f.db,
      localOwners: f.ownerLookup,
      vocabulary: f.vocabulary,
      progressUpdates: f.updates,
      progress: ProgressUseCases(
        owners: f.owners,
        queries: DriftProgressQueries(f.db),
        nowUtc: () => at,
      ),
    );
    // Prime unrelated home recommendations on SQLite's real setup clock.
    // Category, word and owner access during handwriting remain live.
    f.home = await f.dependencies.progress!.load();
    return f;
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
    for (final table in db.allTables)
      table.actualTableName: [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                )
                .get())
          Map.of(row.data),
      ],
  };

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    updates.dispose();
    var closed = false;
    final closing = db.close().whenComplete(() => closed = true);
    await _wait(tester, () => closed);
    await closing;
    await tester.pump();
  }
}

final class _Guest extends Fake implements GuestSessionService {}

final class _OwnerLookup extends Fake implements LocalOwnerRepository {
  _OwnerLookup(this.delegate);
  final LocalOwnerRepository delegate;
  bool failNextLookup = false;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    if (failNextLookup) {
      failNextLookup = false;
      throw StateError('synthetic owner lookup failure');
    }
    return delegate.getOrCreateActiveOwner();
  }
}
