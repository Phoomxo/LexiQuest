import 'package:flutter/material.dart';
import '../../support/r15_visual_capture.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/guided_repair.dart';
import 'package:vocab_learning_app/features/learning/presentation/guided_repair_screen.dart';

void main() {
  setUpAll(loadR15Fonts);
  testWidgets('320px text200 repair stays scrollable and renders real fonts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('synthetic-r15-surface'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: M3Theme.thaiFontFamily,
          ),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              appBar: AppBar(title: const Text('ฝึกแก้คำตอบ')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GuidedRepairPanel(
                  state: GuidedRepairState.start(
                    originId: 'original',
                    priorHintLevel: 1,
                  ),
                  contextText: 'The train arrives at the station.',
                  answer: text,
                  busy: false,
                  onHint: () {},
                  onAnswer: () {},
                  onExit: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureR15Surface(tester, 'e31-guided-repair');
    await tester.ensureVisible(find.text('กลับไปบทเรียน'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('assisted practice labels budget and always exposes exit', (
    tester,
  ) async {
    var answers = 0;
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidedRepairPanel(
            state: GuidedRepairState.start(
              originId: 'original',
              priorHintLevel: 1,
            ),
            contextText: 'The train arrives here.',
            answer: text,
            busy: false,
            onHint: () {},
            onAnswer: () => answers++,
            onExit: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('guided practice'), findsOneWidget);
    expect(find.textContaining('0/3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'station');
    await tester.tap(find.text('ตรวจคำตอบฝึก'));
    expect(answers, 1);
    expect(find.text('กลับไปบทเรียน'), findsOneWidget);
  });
  testWidgets('exhausted repair disables inputs and retains exit', (
    tester,
  ) async {
    var state = GuidedRepairState.start(
      originId: 'original',
      priorHintLevel: 2,
    );
    for (var i = 0; i < 3; i++) {
      state = state.answer(correct: false);
    }
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidedRepairPanel(
            state: state,
            contextText: 'Context',
            answer: text,
            busy: false,
            onHint: () {},
            onAnswer: () {},
            onExit: () {},
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.textContaining('ครบจำนวน'), findsOneWidget);
    expect(find.text('กลับไปบทเรียน'), findsOneWidget);
  });
}
