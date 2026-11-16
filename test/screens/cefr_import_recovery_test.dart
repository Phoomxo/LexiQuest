import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as owner_domain;
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_catalog_screen.dart';

final catalog = CefrVocabularyCatalog.fromBytes(
  File(CefrVocabularyCatalog.asset).readAsBytesSync(),
);

class Repository implements VocabularyRepository {
  Repository(this.real);
  final DriftVocabularyRepository real;
  Completer<void>? categories;
  Completer<void>? listing;
  Completer<void>? acknowledgement;
  Object? readError;
  int reads = 0;
  int creates = 0;
  VoidCallback? beforeCreate;
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) async* {
    reads++;
    final wait = categories;
    if (wait != null) await wait.future;
    if (readError != null) throw readError!;
    yield* real.watchCategories(ownerId);
  }

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async {
    if (listing != null) await listing!.future;
    return real.listAllWords(ownerId);
  }

  @override
  Future<VocabularyWord> createWord(VocabularyWord word) async {
    creates++;
    beforeCreate?.call();
    final result = await real.createWord(word);
    if (acknowledgement != null) await acknowledgement!.future;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Fixture {
  Fixture({this.pause});
  final WritePause? pause;
  late final db = AppDatabase(
    pause == null
        ? NativeDatabase.memory()
        : NativeDatabase.memory().interceptWith(pause!),
  );
  late final owners = DriftLocalOwnerRepository(
    db,
    generateId: () => 'au-owner-${ownerId++}',
    nowUtc: () => DateTime.utc(2026),
  );
  late final real = DriftVocabularyRepository(db);
  late final controlledOwners = Owners(owners);
  late final repo = Repository(real);
  late final vocabulary = VocabularyUseCases(
    owners: controlledOwners,
    vocabulary: repo,
    generateId: () => 'au-${id++}',
    nowUtc: () => DateTime.utc(2026),
  );
  final nav = GlobalKey<NavigatorState>();
  final active = ValueNotifier(true);
  final binding = ValueNotifier<VocabularyUseCases?>(null);
  final future = Future.value(catalog);
  int id = 0;
  int ownerId = 0;
  Future<void> mount(WidgetTester tester) async {
    addTearDown(db.close);
    addTearDown(active.dispose);
    addTearDown(binding.dispose);
    final setup = VocabularyUseCases(
      owners: owners,
      vocabulary: real,
      generateId: () => 'setup-${id++}',
      nowUtc: () => DateTime.utc(2026),
    );
    await setup.createCategory('เลือกของฉัน');
    binding.value = vocabulary;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, on, _) => TickerMode(
            enabled: on,
            child: ValueListenableBuilder<VocabularyUseCases?>(
              valueListenable: binding,
              builder: (_, value, _) => CefrVocabularyCatalogScreen(
                catalog: future,
                vocabulary: value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> begin(WidgetTester tester) async {
    final search = find.byKey(const ValueKey('cefr-catalog-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'book');
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('cefr-word-cefrj15:book'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final sense = find.byType(ListTile).first;
    await tester.ensureVisible(sense);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(sense).onTap, isNotNull);
    await tester.tap(sense);
    await pumps(tester);
  }

  Future<void> retire(WidgetTester tester, String how) async {
    switch (how) {
      case 'tab':
        active.value = false;
        await tester.pump();
        active.value = true;
        await tester.pump();
      case 'cover':
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await pumps(tester);
        nav.currentState!.pop();
        await pumps(tester);
      case 'lifecycle':
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      case 'replacement':
        binding.value = VocabularyUseCases(
          owners: owners,
          vocabulary: real,
          generateId: () => 'replacement-${id++}',
          nowUtc: () => DateTime.utc(2026),
        );
        await tester.pump();
      case 'removal':
        binding.value = null;
        await tester.pump();
      case 'dispose':
        await tester.pumpWidget(const MaterialApp(home: Text('removed')));
        await tester.pump();
      case 'owner':
        await (db.update(db.localOwners)..where((o) => o.isActive.equals(true)))
            .write(const LocalOwnersCompanion(isActive: drift.Value(false)));
        await owners.getOrCreateActiveOwner();
    }
  }

  Future<int> count() async =>
      (await db.select(db.vocabularyWords).get()).length;
}

Future<void> pumps(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final failure in [
    const VocabularyNotFoundFailure(),
    const CategoryWordLimitFailure(50),
  ]) {
    testWidgets(
      'AU typed import error ${failure.runtimeType} handles failed owner revalidation',
      (tester) async {
        final f = Fixture();
        await f.mount(tester);
        await f.begin(tester);
        f.repo.beforeCreate = () {
          f.controlledOwners.failing = true;
          throw failure;
        };
        await tester.tap(find.text('เลือกของฉัน'));
        await pumps(tester);
        expect(tester.takeException(), isNull);
        expect(await f.count(), 0);
        expect(
          find.text('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่'),
          findsOneWidget,
        );
      },
    );
  }
  for (final synchronous in [true, false]) {
    testWidgets(
      'AU owner read failure synchronous=$synchronous has safe explicit retry',
      (tester) async {
        final f = Fixture();
        await f.mount(tester);
        f.controlledOwners.failing = true;
        f.controlledOwners.synchronous = synchronous;
        await f.begin(tester);
        expect(
          find.text('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองใหม่'),
          findsOneWidget,
        );
        expect(await f.count(), 0);
        expect(tester.takeException(), isNull);
        f.controlledOwners.failing = false;
        await f.begin(tester);
        await tester.tap(find.text('เลือกของฉัน'));
        await pumps(tester);
        expect(await f.count(), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'AU owner read failure in owned picker retains usable explicit choice',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      f.controlledOwners.failing = true;
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(
        find.text('ยังตรวจสอบคลังคำศัพท์ไม่ได้ กรุณาลองเลือกอีกครั้ง'),
        findsOneWidget,
      );
      expect(await f.count(), 0);
      expect(tester.takeException(), isNull);
      f.controlledOwners.failing = false;
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(await f.count(), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('AU popped category picker callback cannot pop its catalog', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    await f.begin(tester);
    final choose = tester
        .widget<SimpleDialogOption>(
          find.widgetWithText(SimpleDialogOption, 'เลือกของฉัน'),
        )
        .onPressed!;
    f.nav.currentState!.pop();
    await pumps(tester);
    choose();
    await pumps(tester);
    expect(find.byKey(const ValueKey('cefr-catalog-search')), findsOneWidget);
    expect(await f.count(), 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'AU parent pop retires pending category read before disposal completes',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CefrVocabularyCatalogScreen(
            catalog: f.future,
            vocabulary: f.vocabulary,
          ),
        ),
      );
      await tester.pumpAndSettle();
      f.repo.categories = Completer<void>();
      await f.begin(tester);
      expect(f.repo.reads, 1);
      f.nav.currentState!.pop();
      f.repo.categories!.complete();
      await pumps(tester);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(await f.count(), 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AU uncertain committed acknowledgement is truthful and explicit retry is idempotent',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      f.repo.acknowledgement = Completer<void>();
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(await f.count(), 1);
      f.repo.acknowledgement!.completeError(
        StateError('acknowledgement unavailable'),
      );
      await pumps(tester);
      expect(
        find.text('ยังยืนยันผลการเพิ่มคำไม่ได้ กรุณาตรวจคลังหรือลองใหม่'),
        findsOneWidget,
      );
      expect(f.repo.creates, 1);
      f.repo.acknowledgement = null;
      await f.begin(tester);
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(await f.count(), 1);
      expect(f.repo.creates, 1);
      expect(
        find.text('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final table in ['vocabulary_words', 'outbox_operations']) {
    testWidgets(
      'AU retirement after $table insert rolls back word and outbox',
      (tester) async {
        final pause = WritePause(table);
        final f = Fixture(pause: pause);
        await f.mount(tester);
        f.binding.value = VocabularyUseCases(
          owners: f.owners,
          vocabulary: f.real,
          generateId: () => 'partial-${f.id++}',
          nowUtc: () => DateTime.utc(2026),
        );
        await tester.pump();
        await f.begin(tester);
        final before = (await f.db.select(f.db.outboxOperations).get()).length;
        pause.armed = true;
        await tester.tap(find.text('เลือกของฉัน'));
        await pumps(tester);
        expect(pause.entered.isCompleted, isTrue);
        await f.retire(tester, 'lifecycle');
        pause.release.complete();
        await pumps(tester);
        expect(await f.count(), 0);
        expect((await f.db.select(f.db.outboxOperations).get()).length, before);
        expect(tester.takeException(), isNull);
        await f.begin(tester);
        await tester.tap(find.text('เลือกของฉัน'));
        await pumps(tester);
        expect(await f.count(), 1);
        expect(
          (await f.db.select(f.db.outboxOperations).get()).length,
          before + 1,
        );
      },
    );
  }
  for (final how in [
    'tab',
    'cover',
    'lifecycle',
    'replacement',
    'removal',
    'dispose',
    'owner',
  ]) {
    testWidgets('AU pending category read retires on $how', (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.repo.categories = Completer<void>();
      await f.begin(tester);
      expect(f.repo.reads, 1);
      await f.retire(tester, how);
      f.repo.categories!.complete();
      await pumps(tester);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(await f.count(), 0);
      expect(tester.takeException(), isNull);
    });
  }
  for (final how in [
    'tab',
    'cover',
    'lifecycle',
    'replacement',
    'removal',
    'dispose',
    'owner',
  ]) {
    testWidgets('AU owned picker stale choice retires on $how', (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      final option = find.widgetWithText(SimpleDialogOption, 'เลือกของฉัน');
      expect(option, findsOneWidget);
      final choose = tester.widget<SimpleDialogOption>(option).onPressed!;
      await f.retire(tester, how);
      choose();
      await pumps(tester);
      expect(await f.count(), 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'AU duplicate owned category selection imports once and retains catalog',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      final choose = tester
          .widget<SimpleDialogOption>(
            find.widgetWithText(SimpleDialogOption, 'เลือกของฉัน'),
          )
          .onPressed!;
      choose();
      choose();
      await pumps(tester);
      expect(await f.count(), 1);
      expect(f.repo.creates, 1);
      expect(find.byKey(const ValueKey('cefr-catalog-search')), findsOneWidget);
      expect(
        find.text('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('AU category error retains query and allows explicit retry', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    f.repo.readError = StateError('isolated read failed');
    await f.begin(tester);
    expect(
      find.text('ยังเพิ่มคำไม่ได้ กรุณาลองใหม่ ข้อมูลเดิมยังคงอยู่'),
      findsOneWidget,
    );
    expect(await f.count(), 0);
    expect(tester.takeException(), isNull);
    f.repo.readError = null;
    await f.begin(tester);
    await tester.tap(find.text('เลือกของฉัน'));
    await pumps(tester);
    expect(await f.count(), 1);
    expect(tester.takeException(), isNull);
  });
  for (final how in ['tab', 'lifecycle', 'owner']) {
    testWidgets('AU committed import acknowledgement retires on $how', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      f.repo.acknowledgement = Completer<void>();
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(await f.count(), 1);
      await f.retire(tester, how);
      f.repo.acknowledgement!.complete();
      await pumps(tester);
      expect(
        find.text('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้'),
        findsNothing,
      );
      expect(await f.count(), 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'AU canonical import pending existing lookup retires before create',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.begin(tester);
      f.repo.listing = Completer<void>();
      await tester.tap(find.text('เลือกของฉัน'));
      await pumps(tester);
      expect(f.repo.creates, 0);
      await f.retire(tester, 'lifecycle');
      f.repo.listing!.complete();
      await pumps(tester);
      expect(await f.count(), 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class WritePause extends drift.QueryInterceptor {
  WritePause(this.table);
  final String table;
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    if (armed && statement.contains('"$table"')) {
      armed = false;
      entered.complete();
      await release.future;
    }
    return result;
  }
}

class Owners implements LocalOwnerRepository {
  Owners(this.real);
  final LocalOwnerRepository real;
  bool failing = false;
  bool synchronous = false;
  @override
  Future<owner_domain.LocalOwner> getOrCreateActiveOwner() {
    if (failing) {
      if (synchronous) throw StateError('isolated owner read');
      return Future.error(StateError('isolated owner read'));
    }
    return real.getOrCreateActiveOwner();
  }

  @override
  Future<owner_domain.LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      real.bindFirebaseUid(ownerId, uid);
}
