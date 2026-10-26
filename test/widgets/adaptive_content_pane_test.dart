import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/adaptive_content_pane.dart';

void main() {
  for (final size in const [Size(360, 800), Size(1280, 800)]) {
    testWidgets('task pane uses the available width up to 720 on $size', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveContentPane(
              child: ColoredBox(
                key: ValueKey('pane-child'),
                color: Colors.transparent,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(const ValueKey('pane-child')));
      expect(rect.width, size.width > 720 ? 720 : size.width);
      expect(rect.center.dx, size.width / 2);
      expect(rect.height, size.height);
    });
  }
}
