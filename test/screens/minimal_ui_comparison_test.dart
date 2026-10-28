import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(M3Theme.thaiFontFamily)
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final large in [false, true]) {
    testWidgets(
      'learning choices remain reachable ${large ? 'large' : 'normal'}',
      (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const boundary = ValueKey('minimal-comparison');
        await tester.pumpWidget(
          MaterialApp(
            theme: large ? M3Theme.darkTheme : M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: ChooseModeScreen(
              featureRegistry: const BuildFeatureRegistry.allEnabled(),
              lessonModes: buildLessonModeRegistry(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const phase = String.fromEnvironment('UI_CAPTURE_PHASE');
        if (phase.isNotEmpty) {
          final renderer = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundary),
          );
          await tester.runAsync(() async {
            final picture = await renderer.toImage(pixelRatio: 2);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/verification/minimal-ui-20260912/$phase-${large ? '320-text200-dark' : '390-text100-light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
        final quiz = find.byKey(const ValueKey('home/learn/quiz'));
        await tester.ensureVisible(quiz);
        await tester.pumpAndSettle();
        final quizIcon = find
            .descendant(of: quiz, matching: find.byType(Icon))
            .first;
        expect(
          tester.getCenter(quizIcon).dx,
          closeTo(tester.getCenter(quiz).dx, 1),
        );
        final last = find.byKey(
          const ValueKey('home/learn/associative-reading'),
        );
        await tester.scrollUntilVisible(
          last,
          220,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 60,
        );
        await Scrollable.ensureVisible(tester.element(last), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(
          find
              .descendant(of: last, matching: find.byType(InkWell))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
