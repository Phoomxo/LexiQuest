import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/lexical_quiz_setup_dialog.dart';

import '../support/authored_lexical_pack.dart';

void main() {
  testWidgets(
    'configuration validates time and preserves explicit choices at 320px 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LexicalQuizConfiguration? result;
      final entries = authoredLexicalPack().entries.toList();
      final dialog = LexicalQuizSetupDialog(
        packVersionId: 'synthetic-pack',
        packTitle: 'Synthetic pack',
        cefrLevel: 'A2',
        entries: entries,
      );
      entries.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showDialog<LexicalQuizConfiguration>(
                    context: context,
                    builder: (_) => dialog,
                  );
                },
                child: const Text('ตั้งค่า'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ตั้งค่า'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic pack'), findsOneWidget);
      expect(find.text('ระดับแพ็ก CEFR A2'), findsOneWidget);
      final minutes = find.byKey(const ValueKey('definition-time-goal'));
      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '181');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _tap(tester, find.byKey(const ValueKey('definition-start')));
      expect(find.text('ระบุ 1–180 นาที หรือเว้นว่าง'), findsOneWidget);
      expect(result, isNull);
      await tester.ensureVisible(minutes);
      await tester.enterText(minutes, '15');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _tap(
        tester,
        find.widgetWithText(SwitchListTile, 'ปุ่มฟังคำหลังตอบ'),
      );
      await _tap(tester, find.widgetWithText(SwitchListTile, 'ปุ่มขนาดใหญ่'));
      await _tap(tester, find.byKey(const ValueKey('definition-hints')));
      final reducedMotion = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'ลดการเคลื่อนไหว'),
      );
      expect(reducedMotion.value, isTrue);
      expect(reducedMotion.onChanged, isNull);
      await _tap(tester, find.byKey(const ValueKey('definition-start')));
      expect(result!.input, LexicalQuizInput.definitionChoice);
      expect(result!.limit, 2);
      expect(result!.entryCodes, ['cat', 'dog']);
      expect(result!.settings.advisoryMinutes, 15);
      expect(result!.settings.manualAudio, isTrue);
      expect(result!.settings.accessibleInput, isTrue);
      expect(result!.settings.reduceMotion, isTrue);
      expect(result!.hints, QuizHintPolicy.disabled);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a set without authored definitions cannot start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LexicalQuizSetupDialog(
          packVersionId: 'synthetic-pack',
          entries: authoredLexicalPack(includeDefinitions: false).entries,
        ),
      ),
    );
    expect(
      find.text('ชุดนี้ยังไม่มีนิยามสำหรับฝึก เลือกชุดคำศัพท์อื่นได้'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('definition-start')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
