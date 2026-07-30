import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  group('B3 Associative Reading Session Screen Tests', () {
    testWidgets('Renders stages and progresses through 6 stages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B2',
            targetWords: ['ephemeral', 'resilient'],
            passageText:
                'Life is filled with ephemeral moments that require a resilient spirit to appreciate.',
          ),
        ),
      );

      expect(find.text('Associative Reading (B2)'), findsOneWidget);
      expect(find.text('Stage 1: Supported Reading'), findsOneWidget);
      expect(find.textContaining('ephemeral moments'), findsOneWidget);

      // Tap Complete & Continue for Stage 1 -> Stage 2
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 2: Cue Fading'), findsOneWidget);

      // Tap Complete & Continue for Stage 2 -> Stage 3
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 3: Active Recall'), findsOneWidget);

      // Tap Complete & Continue for Stage 3 -> Stage 4
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 4: Memory Association'), findsOneWidget);

      // Tap Complete & Continue for Stage 4 -> Stage 5
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 5: Context Transfer'), findsOneWidget);

      // Tap Complete & Continue for Stage 5 -> Stage 6
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 6: Finish'), findsOneWidget);
      expect(find.text('Ready to finish'), findsOneWidget);
    });
  });
}
