import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
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

      // Stage 1 -> Stage 2
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 2: Cue Fading'), findsOneWidget);

      // Stage 2 -> Stage 3
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 3: Active Recall'), findsOneWidget);

      // Stage 3 -> Stage 4
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 4: Memory Association'), findsOneWidget);

      // Stage 4 -> Stage 5
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 5: Context Transfer'), findsOneWidget);

      // Stage 5 -> Stage 6
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 6: Finish'), findsOneWidget);
      expect(find.text('Ready to finish'), findsOneWidget);
    });

    // ── Stage 3 — Active Recall ────────────────────────────────────────────

    testWidgets('Stage 3 shows one TextField per target word', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'B1',
            targetWords: ['ephemeral', 'resilient'],
            passageText: 'Test passage.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Stage 3 (skip stages 1 and 2).
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Word 1'), findsOneWidget);
      expect(find.text('Word 2'), findsOneWidget);
    });

    // ── Stage 4 — Memory Association ──────────────────────────────────────

    testWidgets('Stage 4 saves associations via AssociativeLearningPort', (
      tester,
    ) async {
      final adapter = InMemoryAssociativeLearningAdapter();

      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            passageText: 'The banana is yellow.',
            associativeLearning: adapter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Stage 4.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Complete & Continue'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Stage 4: Memory Association'), findsOneWidget);

      // Enter a cue for 'banana'.
      await tester.enterText(find.byType(TextField).first, 'yellow fruit');
      await tester.pumpAndSettle();

      // Advance to Stage 5 — triggers _saveAssociations.
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 5: Context Transfer'), findsOneWidget);

      // Association must be persisted in the in-memory adapter.
      final associations = await adapter.getAssociationsForWord(
        'local',
        'banana',
      );
      expect(associations, hasLength(1));
      expect(associations.first.content, 'yellow fruit');
      expect(associations.first.type, 'keyword');
    });
  });
}
