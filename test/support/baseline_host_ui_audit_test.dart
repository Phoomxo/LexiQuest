import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

import '../../integration_test/support/native_baseline_cases.dart';
import '../../integration_test/support/native_baseline_fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  debugPrint('BN action $key');
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('bn-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File(
      'docs/development/ux-delivery/evidence/S01-BN-runs/host-renders/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
  debugPrint('BN captured $name');
}

void main() {
  setUpAll(() async {
    final font = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'BN canonical phone render and actions at ${scale}x',
      (tester) async {
        // Raster review needs real elevation shadows, not test-only outlines.
        final priorDisableShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = priorDisableShadows);
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final fixture = (await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('bn-host-');
          final fixture = await NativeBaselineFixture.open(
            root,
            'bm-bn-host',
            seed: true,
          );
          await fixture.seed();
          await fixture.changePreferenceAndCreateWord(changeDisplay: false);
          return fixture;
        }))!;
        final dependencies = baselineDependencies(fixture);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('bn-capture'),
              child: MyApp(dependencies: dependencies, ownsDependencies: false),
            ),
          );
          await settle(tester);
          for (final (index, id)
              in NavigationGlossary.mainDestinationIds.indexed) {
            await tapKey(tester, id);
            expect(
              tester
                  .widget<NavigationBar>(find.byType(NavigationBar))
                  .selectedIndex,
              index,
            );
            final size = tester.getSize(find.byKey(ValueKey(id)));
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
            final label = NavigationGlossary.require(id).semanticsLabel;
            final node = tester.getSemantics(
              find.bySemanticsLabel(RegExp(RegExp.escape(label))).first,
            );
            expect(
              node.getSemanticsData().flagsCollection.isSelected,
              ui.Tristate.isTrue,
            );
            await capture(
              tester,
              '${index + 1}-${id.split('/').last}-${scale}x',
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            if (id == 'home/learn') {
              await tapKey(tester, 'learn-show-all-modes');
              expect(find.text('ซ่อนโหมดฝึก'), findsOneWidget);
              await tapKey(tester, 'learn-show-all-modes');
            }
            if (id == 'home/profile') {
              await tester.tap(find.text('ลองอีกครั้ง'));
              await settle(tester);
              expect(
                find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'),
                findsOneWidget,
              );
            }
          }
          await tapKey(tester, 'profile/settings');
          expect(find.byType(SettingScreen), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await settle(tester);
          await tapKey(tester, 'home/today');
          await tapKey(tester, 'today-unavailable-practice');
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1,
          );
          await tapKey(tester, 'legacy-drawer-button');
          await tapKey(tester, 'drawer/settings');
          expect(find.byType(SettingScreen), findsOneWidget);
          await capture(tester, '5-settings-${scale}x');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          expect(
            find.text(
              NavigationGlossary.require(
                'settings/change-password',
              ).fullThaiLabel,
            ),
            findsNothing,
          );
          expect(
            find.text(
              NavigationGlossary.require('settings/logout').fullThaiLabel,
            ),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('erase-local-data')), findsNothing);
          final cloud = find.text(
            NavigationGlossary.require('settings/cloud-status').fullThaiLabel,
          );
          await tester.ensureVisible(cloud);
          await settle(tester);
          await capture(tester, '8-settings-lower-${scale}x');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tapKey(tester, 'settings/offline-content');
          expect(find.byType(OfflineContentManagerScreen), findsOneWidget);
          await capture(tester, '6-offline-${scale}x');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tester.tap(find.text('รายละเอียดไฟล์'));
          await settle(tester);
          await capture(tester, '9-offline-details-${scale}x');
          await tester.tap(find.byType(BackButton));
          await settle(tester);
          expect(find.byType(SettingScreen), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          await settle(tester);
          await tapKey(tester, 'home/vocabulary');
          final category = (await baselineAwait(
            tester,
            () => fixture.database
                .select(fixture.database.vocabularyCategories)
                .get(),
          )).single;
          await tapKey(tester, category.id);
          expect(find.byType(VocabListScreen), findsOneWidget);
          expect(find.text('synthetic'), findsWidgets);
          await capture(tester, '10-vocabulary-words-${scale}x');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          final search = find.bySemanticsLabel('ค้นหาคำศัพท์');
          expect(search, findsOneWidget);
          final searchData = tester.getSemantics(search).getSemanticsData();
          expect(searchData.flagsCollection.isTextField, isTrue);
          tester.semantics.performAction(
            find.semantics.byLabel('ค้นหาคำศัพท์'),
            ui.SemanticsAction.tap,
          );
          await settle(tester);
          debugPrint(
            'BN focused search: ${tester.getSemantics(search).toStringDeep()}',
          );
          // Flutter exposes setText only after the editable field has focus.
          expect(
            tester
                .getSemantics(search)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.setText),
            isTrue,
          );
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
          await tester.enterText(
            find.byType(TextField),
            'ไม่มีคำนี้ในข้อมูลสังเคราะห์',
          );
          await settle(tester);
          expect(find.text('ไม่พบคำศัพท์ที่ตรงกับคำค้น'), findsOneWidget);
          await capture(tester, '11-search-empty-${scale}x');
          await tester.enterText(find.byType(TextField), 'synthetic');
          await settle(tester);
          expect(find.text('synthetic'), findsWidgets);
          await tester.tap(find.byType(BackButton));
          await settle(tester);
          await tapKey(tester, 'add-category');
          final field = find.byKey(const ValueKey('category-name-field'));
          expect(field, findsOneWidget);
          await tapKey(tester, 'save-category');
          expect(find.text('กรุณากรอกชื่อหมวดหมู่ให้ถูกต้อง'), findsOneWidget);
          await tester.tap(field);
          await tester.enterText(
            field,
            'หมวดหมู่สังเคราะห์สำหรับตรวจคีย์บอร์ด',
          );
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          // Empty-name feedback includes a retry control before dialog actions.
          expect(
            Focus.of(tester.element(find.text('ลองใหม่'))).hasFocus,
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            Focus.of(tester.element(find.text('ยกเลิก'))).hasFocus,
            isTrue,
          );
          await capture(tester, '7-category-dialog-${scale}x');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settle(tester);
          expect(field, findsNothing);
          final snapshot = await baselineAwait(tester, fixture.snapshot);
          expect(snapshot['externalCalls'], 0);
        } finally {
          debugDisableShadows = priorDisableShadows;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          semantics.dispose();
          (dependencies.features as RuntimeFeatureRegistry).dispose();
          dependencies.quest.dispose();
          await baselineAwait(tester, fixture.close);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
