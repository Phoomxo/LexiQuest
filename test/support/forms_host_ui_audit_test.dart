import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_practice_examples.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

import '../../integration_test/support/native_baseline_cases.dart';
import '../../integration_test/support/native_baseline_fixture.dart';

const _evidence = 'docs/development/ux-delivery/evidence/S01-BP-runs';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await _settle(tester);
  await tester.tap(target);
  await _settle(tester);
}

Finder _key(String key) => find.byKey(ValueKey(key));

bool _focused(Finder target) {
  final element = target.evaluate().single;
  var found = FocusManager.instance.primaryFocus?.context == element;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
    ancestor,
  ) {
    found |= ancestor == element;
    return !found;
  });
  return found;
}

Future<void> _keyboardActivate(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  for (var i = 0; !_focused(target) && i < 16; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settle(tester);
  }
  expect(
    _focused(target),
    isTrue,
    reason: 'Visible action must be keyboard reachable',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _settle(tester);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('bp-capture'),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('$_evidence/host-renders/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
  debugPrint('BP HOST SYNTHETIC captured $name');
}

// Compare every existing application table except the two explicitly mutated
// by a canonical vocabulary save. No fake earning/session/research authority.
Future<Map<String, Object?>> _protectedRows(
  NativeBaselineFixture fixture,
) async {
  final result = <String, Object?>{};
  final names = await fixture.database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      )
      .get();
  for (final row in names) {
    final name = row.read<String>('name');
    if (name.startsWith('sqlite_') ||
        name == 'vocabulary_words' ||
        name == 'outbox_operations') {
      continue;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      throw StateError('Unexpected fixture table');
    }
    result[name] =
        (await fixture.database
                .customSelect('SELECT * FROM $name ORDER BY 1')
                .get())
            .map((r) => r.data)
            .toList();
  }
  return result;
}

void main() {
  setUpAll(() async {
    timezone_data.initializeTimeZones();
    await CefrPracticeExamples.load();
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'BP routed quest and vocabulary form actions ${scale}x',
      (tester) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final fixture = (await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('bp-host-');
          final fixture = await NativeBaselineFixture.open(
            root,
            'bm-bp-host',
            seed: true,
          );
          await fixture.seed();
          await fixture.changePreferenceAndCreateWord(changeDisplay: false);
          return fixture;
        }))!;
        final dependencies = baselineDependencies(fixture);
        final semantics = tester.ensureSemantics();
        final previousNetwork = HttpOverrides.current;
        HttpOverrides.global = fixture.network;
        try {
          final baseline = await baselineAwait(tester, fixture.snapshot);
          var protectedBefore = await baselineAwait(
            tester,
            () => _protectedRows(fixture),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('bp-capture'),
              child: MyApp(dependencies: dependencies, ownsDependencies: false),
            ),
          );
          await _settle(tester);
          await _tap(tester, _key('legacy-drawer-button'));
          await _tap(tester, _key('drawer/rewards/quests'));
          expect(find.byType(QuestStatusScreen), findsOneWidget);
          expect(find.byType(QuestStatusEmpty), findsOneWidget);
          expect(find.text('ยังไม่มีภารกิจ'), findsOneWidget);
          await _capture(tester, '01-quest-empty-${scale}x');
          await _keyboardActivate(tester, find.byType(BackButton));
          expect(find.byType(QuestStatusScreen), findsNothing);

          // Seed only an existing daily quest in this disposable fixture. This
          // is setup for viewing details, never an answer or reward operation.
          final owner = await baselineAwait(
            tester,
            fixture.owners.getOrCreateActiveOwner,
          );
          await baselineAwait(
            tester,
            () => dependencies.quest.refreshDaily(expectedOwnerId: owner.id),
          );
          final seeded = await baselineAwait(
            tester,
            () => _protectedRows(fixture),
          );
          for (final table in protectedBefore.keys.where(
            (name) => !name.startsWith('quest_'),
          )) {
            expect(
              seeded[table],
              protectedBefore[table],
              reason: 'Quest fixture setup must preserve $table',
            );
          }
          protectedBefore = seeded;
          expect(await baselineAwait(tester, fixture.snapshot), baseline);
          await _tap(tester, _key('legacy-drawer-button'));
          await _tap(tester, _key('drawer/rewards/quests'));
          expect(find.text('กำลังทำ'), findsOneWidget);
          expect(find.textContaining('0 จาก 5'), findsOneWidget);
          await _capture(tester, '10-quest-active-${scale}x');
          final details = find.byType(ExpansionTile);
          await _tap(tester, details);
          final reward = find.textContaining('ไม่ใช่ยอดที่ได้รับแล้ว');
          await tester.ensureVisible(reward);
          await _settle(tester);
          expect(reward, findsOneWidget);
          await _capture(tester, '11-quest-details-${scale}x');
          await _keyboardActivate(tester, details);
          expect(reward, findsNothing);
          await _tap(tester, find.byType(BackButton));
          expect(
            await baselineAwait(tester, () => _protectedRows(fixture)),
            protectedBefore,
          );
          // The existing lifecycle render test uses 800px. Exercise its longest
          // status label at phone width using canonical expiry on synthetic data.
          await baselineAwait(
            tester,
            () => dependencies.quest.repository.expireStaleInstances(
              ownerId: owner.id,
              nowUtc: DateTime.utc(2026, 9, 29),
            ),
          );
          final expired = await baselineAwait(
            tester,
            () => _protectedRows(fixture),
          );
          for (final table in protectedBefore.keys.where(
            (name) => !name.startsWith('quest_'),
          )) {
            expect(expired[table], protectedBefore[table]);
          }
          protectedBefore = expired;
          await _tap(tester, _key('legacy-drawer-button'));
          await _tap(tester, _key('drawer/rewards/quests'));
          expect(find.text('ทำได้ในครั้งถัดไป'), findsOneWidget);
          await _capture(tester, '12-quest-expired-${scale}x');
          await _tap(tester, find.byType(BackButton));

          await _tap(tester, _key('home/vocabulary'));
          final category = (await baselineAwait(
            tester,
            () => fixture.database
                .select(fixture.database.vocabularyCategories)
                .get(),
          )).single;
          await _tap(tester, _key(category.id));
          expect(find.byType(VocabListScreen), findsOneWidget);
          await _tap(tester, _key('add-word'));
          expect(find.byType(AddWordScreen), findsOneWidget);
          await _capture(tester, '02-add-empty-${scale}x');
          final cefrLabel = tester.renderObject<RenderParagraph>(
            find.text('ระดับ CEFR (ไม่บังคับ)'),
          );
          expect(
            cefrLabel.didExceedMaxLines,
            isFalse,
            reason:
                'Optional CEFR label must be readable before choosing a level',
          );
          await _tap(tester, _key('save-word'));
          expect(
            find.text('กรุณากรอกข้อมูลให้ครบและไม่เกินความยาวที่กำหนด'),
            findsOneWidget,
          );
          await _capture(tester, '03-add-validation-${scale}x');
          expect(await baselineAwait(tester, fixture.snapshot), baseline);
          await tester.enterText(_key('word-field'), 'cancelled-synthetic');
          await _tap(tester, find.byType(BackButton));
          expect(find.byType(VocabListScreen), findsOneWidget);
          expect(await baselineAwait(tester, fixture.snapshot), baseline);

          await _tap(tester, _key('add-word'));
          await _tap(tester, _key('word-field'));
          final fieldSemantics = tester
              .getSemantics(_key('word-field'))
              .getSemanticsData();
          expect(fieldSemantics.flagsCollection.isTextField, isTrue);
          expect(fieldSemantics.hasAction(ui.SemanticsAction.setText), isTrue);
          await tester.enterText(_key('word-field'), 'synthetic-bp');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _settle(tester);
          expect(_focused(_key('meaning-field')), isTrue);
          await tester.enterText(
            _key('meaning-field'),
            'คำสังเคราะห์สำหรับตรวจแบบฟอร์ม',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _settle(tester);
          expect(_focused(_key('part-of-speech-field')), isTrue);
          await tester.enterText(_key('part-of-speech-field'), 'noun');
          await _capture(tester, '04-add-focused-${scale}x');
          await _tap(tester, find.byType(DropdownButtonFormField<String>));
          await _capture(tester, '05-cefr-chooser-${scale}x');
          await _tap(tester, find.text('A1').last);
          await tester.ensureVisible(_key('save-word'));
          await _settle(tester);
          await _capture(tester, '06-add-ready-${scale}x');
          await _keyboardActivate(tester, _key('save-word'));
          expect(find.byType(AddWordScreen), findsNothing);
          expect(find.byType(VocabListScreen), findsOneWidget);
          final added = (await baselineAwait(
            tester,
            () => fixture.vocabulary.watchWords(category.id).first,
          )).singleWhere((word) => word.spelling == 'synthetic-bp');
          expect(added.meaning, 'คำสังเคราะห์สำหรับตรวจแบบฟอร์ม');
          expect(added.cefrLevel, 'A1');
          await _capture(tester, '07-list-added-${scale}x');

          await _tap(tester, find.text('synthetic-bp'));
          expect(find.text('แก้ไขคำศัพท์'), findsOneWidget);
          expect(
            tester.widget<TextField>(_key('meaning-field')).controller!.text,
            added.meaning,
          );
          await _capture(tester, '08-edit-loaded-${scale}x');
          await tester.enterText(_key('meaning-field'), 'cancelled edit');
          await _keyboardActivate(tester, find.byType(BackButton));
          final cancelled = (await baselineAwait(
            tester,
            () => fixture.vocabulary.watchWords(category.id).first,
          )).singleWhere((word) => word.id == added.id);
          expect(cancelled.meaning, added.meaning);
          expect(cancelled.localRevision, added.localRevision);

          await _tap(tester, find.text('synthetic-bp'));
          await tester.enterText(
            _key('meaning-field'),
            'แก้ไขคำสังเคราะห์แล้ว',
          );
          await _tap(tester, _key('save-word'));
          expect(find.byType(AddWordScreen), findsNothing);
          final words = await baselineAwait(
            tester,
            () => fixture.vocabulary.watchWords(category.id).first,
          );
          expect(words, hasLength(2));
          final edited = words.singleWhere((word) => word.id == added.id);
          expect(edited.meaning, 'แก้ไขคำสังเคราะห์แล้ว');
          expect(edited.localRevision, added.localRevision + 1);
          expect(edited.cefrLevel, 'A1');
          expect(
            words.singleWhere((word) => word.spelling == 'synthetic').meaning,
            'fixture only',
          );
          await _capture(tester, '09-list-edited-${scale}x');
          await _tap(tester, find.byType(BackButton));
          expect(find.byType(VocabListScreen), findsNothing);
          expect(
            await baselineAwait(tester, () => _protectedRows(fixture)),
            protectedBefore,
          );
          final outbox = await baselineAwait(
            tester,
            () => fixture.database
                .customSelect(
                  'SELECT entity_type,state,attempt_count FROM outbox_operations',
                )
                .get(),
          );
          expect(outbox, isNotEmpty);
          for (final row in outbox) {
            expect(row.read<String>('entity_type'), isIn(['word', 'category']));
            expect(row.read<String>('state'), 'pending');
            expect(row.read<int>('attempt_count'), 0);
          }
          expect(fixture.network.calls, 0);
          expect(fixture.gatewayCalls, 0);
          await tester.runAsync(
            () => File('$_evidence/isolation-${scale}x.json').writeAsString(
              jsonEncode({
                'scope': 'HOST SYNTHETIC',
                'protectedTableCount': protectedBefore.length,
                'protectedTablesUnchanged': true,
                'ordinaryOutboxRows': outbox.length,
                'wordCount': words.length,
                'addedThenEditedWordId': edited.id,
                'revisionBeforeEdit': added.localRevision,
                'revisionAfterEdit': edited.localRevision,
                'httpCalls': fixture.network.calls,
                'gatewayCalls': fixture.gatewayCalls,
                'disposableFixture': fixture.directory.path,
              }),
            ),
          );
        } finally {
          HttpOverrides.global = previousNetwork;
          debugDisableShadows = shadows;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          semantics.dispose();
          (dependencies.features as RuntimeFeatureRegistry).dispose();
          dependencies.quest.dispose();
          await baselineAwait(tester, fixture.close);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
