import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/boss_battle_screen.dart';

void main() {
  testWidgets('BossBattleScreen renders HP bar and handles attack damage', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BossBattleScreen(
          bossName: 'Vocab Titan',
          initialBossHp: 100,
          questions: [
            {'word': 'ephemeral', 'translation': 'ชั่วคราว'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vocab Titan'), findsOneWidget);
    expect(find.text('HP: 100 / 100'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ephemeral');
    await tester.tap(find.text('โจมตีบอส!'));
    await tester.pumpAndSettle();

    expect(find.text('HP: 65 / 100'), findsOneWidget);
  });
}
