import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  testWidgets('ProfileSettingsScreen displays user rank and accent settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileSettingsScreen(
          userName: 'คุณเพชร (Khun Phet)',
          totalXp: 2000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('คุณเพชร (Khun Phet)'), findsOneWidget);
    expect(find.text('ยศ: Gold (ทอง)'), findsOneWidget);
    expect(find.text('⚙️ ตั้งค่าเสียง AI OmniVoice'), findsOneWidget);
  });
}
