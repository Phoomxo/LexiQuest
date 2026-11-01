import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';

void main() {
  testWidgets(
    'actual import previews bytes before explicit canonical installation',
    (tester) async {
      final h = (await tester.runAsync(_Harness.open))!;
      final pack = _pack();
      var pickerCalls = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: LearningPackCatalogScreen(
              packs: h.packs,
              pickFile: () async {
                pickerCalls++;
                return XFile.fromData(pack.bytes, name: 'synthetic.json');
              },
            ),
          ),
        );
        await _readyToImport(tester);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('pack-import')))
              .onPressed,
          isNotNull,
          reason: 'The initial owner read must settle before importing',
        );
        await tester.tap(find.byKey(const ValueKey('pack-import')));
        await _untilCondition(tester, () => pickerCalls == 1);
        await _until(
          tester,
          find.byKey(const ValueKey('pack-confirm-install')),
        );
        expect(find.text('Synthetic UI pack'), findsWidgets);
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          0,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        await tester.ensureVisible(
          find.byKey(const ValueKey('pack-confirm-install')),
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pack-confirm-install')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('pack-confirm-install')));
        await _until(tester, find.text('ติดตั้งแพ็กบทเรียนแล้ว'));
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          1,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 2);
        expect(
          await tester.runAsync(() => h.count('lexical_content_snapshots')),
          2,
        );
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.close);
      }
    },
  );

  testWidgets('native picker result before resume remains a verified preview', (
    tester,
  ) async {
    final h = (await tester.runAsync(_Harness.open))!;
    final picked = Completer<XFile?>();
    var pickerCalls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackCatalogScreen(
            packs: h.packs,
            pickFile: () {
              pickerCalls++;
              return picked.future;
            },
          ),
        ),
      );
      await _readyToImport(tester);
      await tester.tap(find.byKey(const ValueKey('pack-import')));
      await _untilCondition(tester, () => pickerCalls == 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      picked.complete(XFile.fromData(_pack().bytes, name: 'synthetic.json'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 0);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _untilCondition(tester, () {
        final button = find.byKey(const ValueKey('pack-confirm-install'));
        return button.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(button).onPressed != null;
      });
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 0);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pack-confirm-install')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pack-confirm-install')));
      await _until(tester, find.text('ติดตั้งแพ็กบทเรียนแล้ว'));
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 2);
      expect(tester.takeException(), isNull);
    } finally {
      if (!picked.isCompleted) picked.complete(null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
    }
  });
}

Future<void> _readyToImport(WidgetTester tester) => _untilCondition(tester, () {
  final finder = find.byKey(const ValueKey('pack-import'));
  return finder.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(finder).onPressed != null;
});

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 100; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(
    finder,
    findsWidgets,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .join(' | '),
  );
}

Future<void> _untilCondition(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 100; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail(
    'Synthetic pack UI did not reach its expected state: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
  );
}

LearningPack _pack() => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-ui-pack',
      version: '1',
      title: 'Synthetic UI pack',
      objectives: ['Synthetic objective'],
      cefrLevel: 'A1',
      language: 'en',
      meaningLanguage: 'en',
      provenance: const LearningPackProvenance(
        author: 'Synthetic author',
        source: 'Synthetic source',
        license: 'Synthetic test only',
        attribution: 'No real publisher',
      ),
    ),
    entries: [
      LearningPackEntry(
        code: 'cat',
        spelling: 'cat',
        meaning: 'a cat',
        partOfSpeech: 'noun',
        definition: 'A small pet that meows.',
        examples: const [LearningPackExample(text: 'The cat sleeps.')],
      ),
      LearningPackEntry(
        code: 'dog',
        spelling: 'dog',
        meaning: 'a dog',
        partOfSpeech: 'noun',
        definition: 'A pet that barks.',
      ),
    ],
  ),
);

final class _Harness {
  _Harness(this.database, this.packs);
  final AppDatabase database;
  final LearningPackUseCases packs;
  static Future<_Harness> open() async {
    final database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'synthetic-ui-owner',
            createdAtUtcMs: 1,
            isActive: const Value(true),
          ),
        );
    var id = 0;
    final packs = LearningPackUseCases(
      repository: DriftLearningPackRepository(
        database: database,
        ownerWrites: DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => DateTime.utc(2026, 11, 1),
        ),
      ),
      nowUtc: () => DateTime.utc(2026, 11, 1),
      generateId: () => 'synthetic-ui-command:${++id}',
    );
    return _Harness(database, packs);
  }

  Future<int> count(String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS n FROM "$table"')
              .getSingle())
          .read<int>('n');
  Future<void> close() async {
    await packs.dispose();
    await database.close();
  }
}
