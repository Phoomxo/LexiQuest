import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/accent_selector_widget.dart';

void main() {
  testWidgets(
    'AccentSelectorWidget renders choice chips and triggers callback',
    (WidgetTester tester) async {
      VoiceAccent selected = VoiceAccent.us;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: AccentSelectorWidget(
                  selectedAccent: selected,
                  onAccentChanged: (accent) {
                    setState(() {
                      selected = accent;
                    });
                  },
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เลือกสำเนียงเสียงอ่าน AI OmniVoice:'), findsOneWidget);
      expect(find.text('อเมริกัน 🇺🇸'), findsOneWidget);
      expect(find.text('อังกฤษ 🇬🇧'), findsOneWidget);

      await tester.tap(find.text('อังกฤษ 🇬🇧'));
      await tester.pumpAndSettle();

      expect(selected, VoiceAccent.uk);
    },
  );
}
