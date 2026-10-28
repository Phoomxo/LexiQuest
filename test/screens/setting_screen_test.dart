import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  testWidgets(
    'settings hides wallpaper selection while remote economy is disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingScreen(profileData: {'first_name': 'Phet'}),
        ),
      );

      expect(find.byIcon(Icons.wallpaper), findsNothing);
    },
  );
}
