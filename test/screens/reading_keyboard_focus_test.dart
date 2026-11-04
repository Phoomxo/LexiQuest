import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  for (final stage in [3, 4, 5]) {
    testWidgets('stage $stage keeps input focus when the keyboard opens', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        const MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: '',
            targetWords: [
              (spelling: 'station', id: null, contentRevision: null),
            ],
            passageText: 'The station is open.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var current = 1; current < stage; current++) {
        await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
        await tester.pumpAndSettle();
      }
      final field = find.byType(EditableText).first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      final focus = tester.widget<EditableText>(field).focusNode;
      expect(focus.hasFocus, isTrue);
      const draft = TextEditingValue(
        text: 'draft',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 5),
      );
      tester.testTextInput.updateEditingValue(draft);
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final resized = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(resized.focusNode, same(focus));
      expect(resized.focusNode.hasFocus, isTrue);
      expect(resized.controller.value, draft);

      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      final restored = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(restored.focusNode, same(focus));
      expect(restored.focusNode.hasFocus, isTrue);
      expect(restored.controller.value, draft);

      const continued = TextEditingValue(
        text: 'draft continued',
        selection: TextSelection.collapsed(offset: 15),
      );
      tester.testTextInput.updateEditingValue(continued);
      await tester.pump();
      expect(restored.controller.value, continued);
    });
  }
}
