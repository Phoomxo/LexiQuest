import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/presentation/lesson_scaffold.dart';

void main() {
  for (final size in [const Size(320, 700), const Size(1400, 900)]) {
    testWidgets('lesson actions stay reachable at $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var exits = 0;
      var submissions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: LessonScaffold(
            title: 'อ่านนิยามแล้วพิมพ์คำศัพท์',
            leading: BackButton(onPressed: () => exits++),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const LessonProgress(current: 2, total: 5),
                const SizedBox(height: 700),
                FilledButton(
                  onPressed: () => submissions++,
                  child: const Text('บันทึกคำตอบ'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('คำถาม 2 จาก 5'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .4,
      );
      expect(
        tester.getSize(find.byType(ListView)).width,
        lessThanOrEqualTo(720),
      );
      await tester.scrollUntilVisible(find.text('บันทึกคำตอบ'), 200);
      await tester.tap(find.text('บันทึกคำตอบ'));
      await tester.tap(find.byType(BackButton));
      expect(submissions, 1);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
