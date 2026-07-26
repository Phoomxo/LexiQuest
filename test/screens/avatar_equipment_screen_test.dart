import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';

void main() {
  testWidgets('AvatarEquipmentScreen renders equipped avatar and items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AvatarEquipmentScreen()));

    expect(find.text('Vocabulary Warrior'), findsOneWidget);
    expect(find.textContaining('Damage:'), findsOneWidget);
    expect(find.textContaining('IPA Crown'), findsOneWidget);
  });
}
